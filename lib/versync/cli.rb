require "yaml"
require "time"

module Versync
  class CLI
    COMMANDS = %w[init facts sync check].freeze

    def initialize(argv, project_root: Dir.pwd, stdout: $stdout, stderr: $stderr)
      @argv = argv
      @project_root = project_root
      @stdout = stdout
      @stderr = stderr
    end

    def run
      command = @argv.first
      unless COMMANDS.include?(command)
        @stderr.puts "Usage: versync [#{COMMANDS.join('|')}]"
        return 1
      end

      send("run_#{command}")
    end

    private

    attr_reader :project_root

    def config_path
      File.join(project_root, ".versync.yml")
    end

    # Returns a loaded Configuration, or nil after printing a diagnostic
    # to stderr — callers return 1 when this returns nil.
    def load_config
      unless File.exist?(config_path)
        @stderr.puts ".versync.yml not found — run `versync init` first"
        return nil
      end

      Configuration.load(config_path)
    rescue Configuration::InvalidError => e
      @stderr.puts ".versync.yml is invalid: #{e.message}"
      nil
    end

    # Returns a FactsCollector::Result, or nil after printing a
    # diagnostic to stderr.
    def collect_facts(config)
      FactsCollector.new.collect(project_root, config.fact_configs)
    rescue FactsCollector::UnknownAdapterError => e
      @stderr.puts e.message
      nil
    end

    def warn_skipped(skipped)
      skipped.each { |s| @stderr.puts "warning: fact '#{s.name}' unavailable — #{s.reason}" }
    end

    def run_facts
      config = load_config
      return 1 unless config

      result = collect_facts(config)
      return 1 unless result

      result.facts.each { |fact| @stdout.puts "#{fact.name}: #{fact.value} (#{fact.source})" }
      warn_skipped(result.skipped)
      0
    end

    def run_sync
      config = load_config
      return 1 unless config

      result = collect_facts(config)
      return 1 unless result

      generated_at = Time.now
      commit = GitInfo.current_sha(project_root)

      markdown = Renderers::Markdown.new(facts: result.facts, generated_at: generated_at, commit: commit).render
      json = Renderers::Json.new(facts: result.facts, generated_at: generated_at, commit: commit).render

      File.write(File.join(project_root, config.markdown_output), markdown)
      File.write(File.join(project_root, config.json_output), json)

      warn_skipped(result.skipped)
      @stdout.puts "Synced #{result.facts.size} fact(s) to #{config.markdown_output} and #{config.json_output}"
      0
    end

    def run_check
      config = load_config
      return 1 unless config

      result = collect_facts(config)
      return 1 unless result

      rendered_markdown = Renderers::Markdown.new(
        facts: result.facts, generated_at: Time.now, commit: GitInfo.current_sha(project_root)
      ).render

      diff = DiffChecker.new(
        project_root: project_root, json_output: config.json_output, markdown_output: config.markdown_output
      ).check(result.facts, rendered_markdown: rendered_markdown)

      warn_skipped(result.skipped)

      if diff.stale?
        @stderr.puts "versync is stale — run `versync sync`:"
        @stderr.puts "  #{config.json_output} does not exist" if diff.missing_output
        if diff.markdown_stale && !diff.missing_output
          @stderr.puts "  #{config.markdown_output} is missing or out of date"
        end
        diff.fact_diffs.each do |d|
          @stderr.puts "  #{d[:name]}: documented=#{d[:before].inspect} actual=#{d[:after].inspect}"
        end
        return 1
      end

      @stdout.puts "versync is up to date"
      0
    end

    def run_init
      1
    end
  end
end

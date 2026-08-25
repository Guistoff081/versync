require "json"

module Versync
  class DiffChecker
    Result = Struct.new(:stale?, :missing_output, :fact_diffs, :markdown_stale, keyword_init: true)

    FOOTER_PATTERN = /^_Last synced:.*_\n?/

    def initialize(project_root:, json_output:, markdown_output:)
      @project_root = project_root
      @json_output = json_output
      @markdown_output = markdown_output
    end

    def check(current_facts, rendered_markdown:)
      json_path = File.join(@project_root, @json_output)
      unless File.exist?(json_path)
        return Result.new(stale?: true, missing_output: true, fact_diffs: [], markdown_stale: true)
      end

      on_disk = JSON.parse(File.read(json_path))
      on_disk_facts = on_disk.fetch("facts", []).map do |f|
        Fact.new(name: f["name"], value: f["value"], source: f["source"])
      end

      fact_diffs = diff_facts(on_disk_facts, current_facts)
      markdown_stale = markdown_stale?(rendered_markdown)

      Result.new(
        stale?: !fact_diffs.empty? || markdown_stale,
        missing_output: false,
        fact_diffs: fact_diffs,
        markdown_stale: markdown_stale
      )
    end

    private

    def markdown_stale?(rendered_markdown)
      markdown_path = File.join(@project_root, @markdown_output)
      return true unless File.exist?(markdown_path)

      strip_footer(File.read(markdown_path)) != strip_footer(rendered_markdown)
    end

    def strip_footer(text)
      text.sub(FOOTER_PATTERN, "")
    end

    def diff_facts(on_disk_facts, current_facts)
      on_disk_by_name = on_disk_facts.to_h { |f| [f.name, f] }
      current_by_name = current_facts.to_h { |f| [f.name, f] }
      names = (on_disk_by_name.keys | current_by_name.keys)

      names.filter_map do |name|
        before = on_disk_by_name[name]
        after = current_by_name[name]
        next nil if before && after && before.value == after.value && before.source == after.source

        { name: name, before: before&.value, after: after&.value }
      end
    end
  end
end

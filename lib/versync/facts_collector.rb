module Versync
  class FactsCollector
    class UnknownAdapterError < StandardError; end

    Result = Struct.new(:facts, :skipped, keyword_init: true)
    Skipped = Struct.new(:name, :reason, keyword_init: true)

    DEFAULT_ADAPTER_REGISTRY = {
      "ruby_version" => -> { Adapters::RubyVersion.new },
      "bundler" => -> { Adapters::Bundler.new },
      "docker_compose" => -> { Adapters::DockerCompose.new }
    }.freeze

    def initialize(adapter_registry: DEFAULT_ADAPTER_REGISTRY)
      @adapter_registry = adapter_registry
    end

    # Returns a Result. Fact configs whose adapter raises
    # Adapters::NotFoundError are reported in `skipped`, not raised —
    # an unavailable fact (e.g. no Redis configured) is expected, not
    # a failure. An unregistered adapter name is a configuration bug
    # and does raise.
    def collect(project_root, fact_configs)
      facts = []
      skipped = []

      fact_configs.each do |fact_config|
        adapter = build_adapter(fact_config.adapter)
        begin
          result = adapter.extract(project_root, fact_config.options)
          facts << Fact.new(name: fact_config.name, value: result.fetch(:value), source: result.fetch(:source))
        rescue Adapters::NotFoundError => e
          skipped << Skipped.new(name: fact_config.name, reason: e.message)
        end
      end

      Result.new(facts: facts, skipped: skipped)
    end

    private

    def build_adapter(adapter_name)
      factory = @adapter_registry.fetch(adapter_name) do
        raise UnknownAdapterError, "unknown adapter '#{adapter_name}'"
      end
      factory.call
    end
  end
end

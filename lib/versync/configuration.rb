require "yaml"

module Versync
  class Configuration
    class InvalidError < StandardError; end

    FactConfig = Struct.new(:name, :adapter, :options, keyword_init: true)

    DEFAULT_MARKDOWN_OUTPUT = "VERSIONS.md"
    DEFAULT_JSON_OUTPUT = "versync.json"

    attr_reader :markdown_output, :json_output, :fact_configs

    def self.load(path)
      raise Errno::ENOENT, path unless File.exist?(path)

      data = YAML.safe_load(File.read(path), aliases: true) || {}
      new(data)
    end

    def initialize(data)
      output = data.fetch("output", {}) || {}
      @markdown_output = output.fetch("markdown", DEFAULT_MARKDOWN_OUTPUT)
      @json_output = output.fetch("json", DEFAULT_JSON_OUTPUT)

      @fact_configs = (data.fetch("facts", {}) || {}).map do |fact_name, fact_data|
        unless fact_data.is_a?(Hash) && fact_data["adapter"]
          raise InvalidError, "fact '#{fact_name}' is missing an 'adapter' key"
        end

        options = fact_data.reject { |key, _| key == "adapter" }
        FactConfig.new(name: fact_name, adapter: fact_data["adapter"], options: options)
      end
    end
  end
end

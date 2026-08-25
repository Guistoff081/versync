require "json"
require "time"

module Versync
  module Renderers
    class Json
      def initialize(facts:, generated_at:, commit:)
        @facts = facts
        @generated_at = generated_at
        @commit = commit
      end

      def render
        JSON.pretty_generate(
          "generated_at" => @generated_at.utc.iso8601,
          "commit" => @commit,
          "facts" => @facts.map { |fact| { "name" => fact.name, "value" => fact.value, "source" => fact.source } }
        )
      end
    end
  end
end

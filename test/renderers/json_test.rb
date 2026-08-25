require "test_helper"
require "json"
require "time"

module Renderers
  class JsonTest < Minitest::Test
    def test_renders_facts_generated_at_and_commit
      facts = [Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version")]
      generated_at = Time.parse("2026-08-25T12:00:00Z")

      output = Versync::Renderers::Json.new(facts: facts, generated_at: generated_at, commit: "abc123").render
      parsed = ::JSON.parse(output)

      assert_equal(
        {
          "generated_at" => "2026-08-25T12:00:00Z",
          "commit" => "abc123",
          "facts" => [{ "name" => "ruby", "value" => "4.0.6", "source" => ".ruby-version" }]
        },
        parsed
      )
    end

    def test_renders_null_commit_when_none_given
      output = Versync::Renderers::Json.new(facts: [], generated_at: Time.parse("2026-08-25T12:00:00Z"), commit: nil).render
      assert_nil ::JSON.parse(output)["commit"]
    end
  end
end

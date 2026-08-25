require "test_helper"

class FactsCollectorTest < Minitest::Test
  def setup
    success_adapter = Class.new(Versync::Adapters::Base) do
      def extract(project_root, options)
        { value: "1.2.3", source: "fake" }
      end
    end.new

    not_found_adapter = Class.new(Versync::Adapters::Base) do
      def extract(project_root, options)
        raise Versync::Adapters::NotFoundError, "nope"
      end
    end.new

    registry = { "fake_success" => -> { success_adapter }, "fake_not_found" => -> { not_found_adapter } }
    @collector = Versync::FactsCollector.new(adapter_registry: registry)
  end

  def test_collects_facts_from_successful_adapters
    configs = [Versync::Configuration::FactConfig.new(name: "ruby", adapter: "fake_success", options: {})]
    result = @collector.collect("/fake/root", configs)

    assert_equal [Versync::Fact.new(name: "ruby", value: "1.2.3", source: "fake")], result.facts
    assert_empty result.skipped
  end

  def test_reports_skipped_facts_whose_adapter_raises_not_found
    configs = [Versync::Configuration::FactConfig.new(name: "missing", adapter: "fake_not_found", options: {})]
    result = @collector.collect("/fake/root", configs)

    assert_empty result.facts
    assert_equal 1, result.skipped.size
    assert_equal "missing", result.skipped.first.name
    assert_equal "nope", result.skipped.first.reason
  end

  def test_raises_unknown_adapter_error
    configs = [Versync::Configuration::FactConfig.new(name: "x", adapter: "nope", options: {})]

    assert_raises(Versync::FactsCollector::UnknownAdapterError) { @collector.collect("/fake/root", configs) }
  end

  def test_default_registry_covers_the_three_shipped_adapters
    default_collector = Versync::FactsCollector.new
    configs = [Versync::Configuration::FactConfig.new(name: "ruby", adapter: "ruby_version", options: {})]

    with_temp_project do |dir|
      copy_fixture("ruby_project", dir)
      result = default_collector.collect(dir, configs)
      assert_equal [Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version")], result.facts
    end
  end

  def test_preserves_config_order_in_facts
    configs = [
      Versync::Configuration::FactConfig.new(name: "b", adapter: "fake_success", options: {}),
      Versync::Configuration::FactConfig.new(name: "a", adapter: "fake_success", options: {})
    ]
    result = @collector.collect("/fake/root", configs)

    assert_equal %w[b a], result.facts.map(&:name)
  end
end

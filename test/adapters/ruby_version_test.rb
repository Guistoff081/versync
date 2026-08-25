require "test_helper"

module Adapters
  class RubyVersionTest < Minitest::Test
    def setup
      @adapter = Versync::Adapters::RubyVersion.new
    end

    def test_available_when_ruby_version_exists
      with_temp_project do |dir|
        copy_fixture("ruby_project", dir)
        assert @adapter.available?(dir)
      end
    end

    def test_not_available_when_ruby_version_missing
      with_temp_project { |dir| refute @adapter.available?(dir) }
    end

    def test_extracts_ruby_version_stripped
      with_temp_project do |dir|
        copy_fixture("ruby_project", dir)
        assert_equal({ value: "4.0.6", source: ".ruby-version" }, @adapter.extract(dir, {}))
      end
    end

    def test_raises_not_found_when_missing
      with_temp_project do |dir|
        assert_raises(Versync::Adapters::NotFoundError) { @adapter.extract(dir, {}) }
      end
    end
  end
end

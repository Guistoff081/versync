require "test_helper"

module Adapters
  class BundlerTest < Minitest::Test
    def setup
      @adapter = Versync::Adapters::Bundler.new
      @dir = Dir.mktmpdir
      copy_fixture("bundler_project", @dir)
    end

    def teardown
      FileUtils.remove_entry(@dir)
    end

    def test_available_when_gemfile_lock_exists
      assert @adapter.available?(@dir)
    end

    def test_extracts_top_level_gem_version
      assert_equal({ value: "8.1.3", source: "Gemfile.lock" }, @adapter.extract(@dir, { "gem" => "rails" }))
    end

    def test_does_not_match_nested_dependency_constraints
      assert_equal({ value: "1.2.2", source: "Gemfile.lock" }, @adapter.extract(@dir, { "gem" => "concurrent-ruby" }))
    end

    def test_raises_not_found_when_gem_missing
      assert_raises(Versync::Adapters::NotFoundError) { @adapter.extract(@dir, { "gem" => "sidekiq" }) }
    end

    def test_raises_not_found_when_no_gem_option
      assert_raises(Versync::Adapters::NotFoundError) { @adapter.extract(@dir, {}) }
    end
  end
end

require "test_helper"

module Adapters
  class BaseTest < Minitest::Test
    def setup
      @adapter = Versync::Adapters::Base.new
    end

    def test_name_raises
      assert_raises(NotImplementedError) { @adapter.name }
    end

    def test_available_raises
      assert_raises(NotImplementedError) { @adapter.available?("/some/root") }
    end

    def test_extract_raises
      assert_raises(NotImplementedError) { @adapter.extract("/some/root", {}) }
    end
  end
end

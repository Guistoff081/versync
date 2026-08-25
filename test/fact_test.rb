require "test_helper"

class FactTest < Minitest::Test
  def test_value_equality
    a = Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version")
    b = Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version")

    assert_equal a, b
  end
end

require "test_helper"

class VersyncTest < Minitest::Test
  def test_has_a_version_number
    refute_nil ::Versync::VERSION
  end
end

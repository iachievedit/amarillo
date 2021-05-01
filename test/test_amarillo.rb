require 'minitest/autorun'

require 'amarillo'

class AmarilloTest < Minitest::Test
  def test_environment
  	a = Amarillo::Environment.new
  	assert_equal(true, a.verify)
  end

  def test_nameservers
  	a = Amarillo::Environment.new
    assert_operator a.get_zone_nameservers.length, :>, 0
  end
end

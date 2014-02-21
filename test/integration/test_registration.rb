require "test_helper"

class TestRegistration < Minitest::Test
  def test_service_is_online_after_registration
    client = Discover::Client.new

    name = "foo"
    port = 1111
    ip   = "127.0.0.1"

    client.register name, port, ip

    service = client.service(name)
    assert_equal 1, service.online.size

    instance = service.online.first
    assert_equal name, instance.name
    assert_equal "#{ip}:#{port}", instance.address
    assert instance.online?
  end
end

require "test_helper"

class TestServiceLeader < DiscoverIntegrationTest
  def test_leader_is_oldest_online_service
    name = "foo"
    ip   = "127.0.0.1"

    service = @client.service(name)
    assert_nil service.leader

    registrations = []
    registrations << @client.register(name, 1111, ip)
    assert_equal "#{ip}:1111", service.leader.address

    registrations << @client.register(name, 2222, ip)
    registrations << @client.register(name, 3333, ip)
    sleep(0.2)
    assert_equal "#{ip}:1111", service.leader.address

    registrations.shift.unregister
    sleep(0.2)
    assert_equal "#{ip}:2222", service.leader.address

    registrations.each(&:unregister)
    sleep(0.2)
    assert_nil service.leader
  end
end

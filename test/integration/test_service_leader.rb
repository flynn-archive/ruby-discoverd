require "test_helper"

class TestServiceLeader < DiscoverIntegrationTest
  class TestLeaderWatcher
    include Celluloid

    attr_reader :leader_updates

    def initialize(service)
      @service        = service
      @leader_updates = []

      async.watch
    end

    def watch
      @service.each_leader do |leader|
        @leader_updates.push leader
      end
    end
  end

  def test_leader_is_oldest_online_service
    name = "foo"
    ip   = "127.0.0.1"

    service = @client.service(name)
    assert_nil service.leader

    registrations = []
    registrations << @client.register(name, 1111, ip)
    sleep(0.5)
    assert_equal "#{ip}:1111", service.leader.address

    registrations << @client.register(name, 2222, ip)
    registrations << @client.register(name, 3333, ip)
    sleep(0.5)
    assert_equal "#{ip}:1111", service.leader.address

    registrations.shift.unregister
    sleep(0.5)
    assert_equal "#{ip}:2222", service.leader.address

    registrations.each(&:unregister)
    sleep(0.5)
    assert_nil service.leader
  end

  def test_leader_changes
    name = "foo"
    ip   = "127.0.0.1"

    service = @client.service(name)
    watcher = TestLeaderWatcher.new(service)
    assert_equal 0, watcher.leader_updates.size

    registrations = []
    registrations << @client.register(name, 1111, ip)
    sleep(0.5)
    assert_equal 1, watcher.leader_updates.size
    assert_equal "#{ip}:1111", watcher.leader_updates.last.address

    registrations << @client.register(name, 2222, ip)
    registrations << @client.register(name, 3333, ip)
    sleep(0.5)
    assert_equal 1, watcher.leader_updates.size
    assert_equal "#{ip}:1111", watcher.leader_updates.last.address

    registrations.shift.unregister
    sleep(0.5)
    assert_equal 2, watcher.leader_updates.size
    assert_equal "#{ip}:2222", watcher.leader_updates.last.address

    registrations.each(&:unregister)
    sleep(0.5)
    assert_equal 3, watcher.leader_updates.size
    assert_equal "#{ip}:3333", watcher.leader_updates.last.address
  end
end

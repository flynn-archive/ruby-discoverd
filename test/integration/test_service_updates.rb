require "test_helper"

class TestServiceUpdates < DiscoverIntegrationTest
  class TestServiceWatcher
    include Celluloid

    attr_reader :updates

    def initialize(service)
      @service = service
      @updates = []
      async.watch
    end

    def watch
      @service.each_update do |update|
        @updates.push update
      end
    end
  end

  def test_registration_triggers_updates
    name = "registration-updates"
    ip   = "127.0.0.1"

    service = @client.service(name)
    watcher = TestServiceWatcher.new(service)

    @client.register name, 1111, ip
    sleep(0.5)
    assert_equal 1, watcher.updates.size
    assert_equal "#{ip}:1111", watcher.updates.last.address

    @client.register name, 2222, ip
    sleep(0.5)
    assert_equal 2, watcher.updates.size
    assert_equal "#{ip}:2222", watcher.updates.last.address

    @client.register name, 1111, ip, { "foo" => "bar" }
    sleep(0.5)
    assert_equal 3, watcher.updates.size
    assert_equal "#{ip}:1111", watcher.updates.last.address
  end
end

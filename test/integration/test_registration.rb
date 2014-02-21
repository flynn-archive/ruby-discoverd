require "test_helper"
require "securerandom"

class TestRegistration < Minitest::Test
  def setup
    etcd_name = SecureRandom.hex
    @etcd_pid = spawn("etcd -name #{etcd_name}", [:out, :err] => "/dev/null")
    sleep(0.2)

    @discoverd_pid = spawn("discoverd", [:out, :err] => "/dev/null")
    sleep(0.2)
  end

  def teardown
    sleep(0.2)
    Process.kill("TERM", @discoverd_pid)
    Process.kill("TERM", @etcd_pid)
    Process.waitall
  end

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

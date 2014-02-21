require "test_helper"
require "securerandom"

class TestRegistration < Minitest::Test
  def setup
    etcd_name = SecureRandom.hex
    @etcd_pid = spawn("etcd -name #{etcd_name}", [:out, :err] => "/dev/null")
    sleep(0.2)

    @discoverd_pid = spawn("discoverd", [:out, :err] => "/dev/null")
    sleep(0.2)

    @client = Discover::Client.new
  end

  def teardown
    sleep(0.2)
    Process.kill("TERM", @discoverd_pid)
    Process.kill("TERM", @etcd_pid)
    Process.waitall
  end

  def test_service_is_online_after_registration
    name       = "foo"
    port       = 1111
    ip         = "127.0.0.1"
    attributes = { "foo" => "bar" }

    @client.register name, port, ip, attributes

    service = @client.service(name)
    assert_equal 1, service.online.size

    instance = service.online.first
    assert_equal name, instance.name
    assert_equal "#{ip}:#{port}", instance.address
    assert_equal attributes, instance.attributes
    assert instance.online?
  end

  def test_changing_service_attributes
    name       = "foo"
    port       = 1111
    ip         = "127.0.0.1"
    attributes = { "foo" => "bar" }

    @client.register name, port, ip, attributes

    service = @client.service(name)
    assert_equal 1, service.online.size

    instance = service.online.first
    assert_equal attributes, instance.attributes

    new_attributes = { "foo" => "baz" }
    @client.register name, port, ip, new_attributes
    assert_equal 1, service.online.size

    instance = service.online.first
    assert_equal new_attributes, instance.attributes
  end

  def test_service_with_filters
    name = "foo"
    ip   = "127.0.0.1"

    matching_attributes     = { "foo" => "bar", "baz" => "qux" }
    non_matching_attributes = { "foo" => "baz", "baz" => "qux" }

    @client.register name, 1111, ip, matching_attributes
    @client.register name, 2222, ip, non_matching_attributes

    service = @client.service(name)
    assert_equal 2, service.online.size

    filtered_service = @client.service(name, "foo" => "bar")
    assert_equal 1, filtered_service.online.size

    instance = filtered_service.online.first
    assert_equal matching_attributes, instance.attributes
  end
end

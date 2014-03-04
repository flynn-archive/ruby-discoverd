require "test_helper"

class TestRegistration < DiscoverIntegrationTest
  class TestRegisterStandby
    include Celluloid

    def initialize(client, name, address)
      @client  = client
      @name    = name
      @address = address
      @elected = false

      async.register_and_standby
    end

    def elected?
      @elected
    end

    def register_and_standby
      @client.register_and_standby(@name, @address)

      @elected = true
    end
  end

  def test_explicit_address
    name    = "explicit-address"
    address = "5.6.7.8:1111"

    @client.register name, address

    service = @client.service(name)
    assert_equal 1, service.online.size

    instance = service.online.first
    assert_equal address, instance.address
  end

  def test_implicit_address
    name    = "implicit-address"
    address = ":1111"

    @client.register name, address

    service = @client.service(name)
    assert_equal 1, service.online.size

    instance = service.online.first
    assert_equal "#{EXTERNAL_IP}:1111", instance.address
  end

  def test_service_is_online_after_registration
    name       = "service-online"
    address    = "127.0.0.1:1111"
    attributes = { "foo" => "bar" }

    @client.register name, address, attributes

    service = @client.service(name)
    assert_equal 1, service.online.size

    instance = service.online.first
    assert_equal name, instance.name
    assert_equal address, instance.address
    assert_equal attributes, instance.attributes
    assert instance.online?

    sleep(11)
    assert_equal 1, service.online.size
  end

  def test_service_is_offline_after_unregister
    name    = "service-offline"
    address = "127.0.0.1:1111"

    registration = @client.register name, address

    service = @client.service(name)
    assert_equal 1, service.online.size

    registration.unregister

    service = @client.service(name)
    assert_equal 0, service.online.size
  end

  def test_changing_service_attributes
    name       = "change-attributes"
    address    = ":1111"
    attributes = { "foo" => "bar" }

    @client.register name, address, attributes

    service = @client.service(name)
    assert_equal 1, service.online.size

    instance = service.online.first
    assert_equal attributes, instance.attributes

    new_attributes = { "foo" => "baz" }
    @client.register name, address, new_attributes

    service = @client.service(name)
    assert_equal 1, service.online.size

    instance = service.online.first
    assert_equal new_attributes, instance.attributes
  end

  def test_service_with_filters
    name = "service-filters"

    matching_attributes     = { "foo" => "bar", "baz" => "qux" }
    non_matching_attributes = { "foo" => "baz", "baz" => "qux" }

    @client.register name, ":1111", matching_attributes
    @client.register name, ":2222", non_matching_attributes

    service = @client.service(name)
    assert_equal 2, service.online.size

    filtered_service = @client.service(name, "foo" => "bar")
    assert_equal 1, filtered_service.online.size

    instance = filtered_service.online.first
    assert_equal matching_attributes, instance.attributes
  end

  def test_register_and_standby
    name = "register-and-standby"

    registrations = []
    registrations << @client.register(name, ":1111")

    standby = TestRegisterStandby.new @client, name, ":2222"
    sleep(0.5)
    assert !standby.elected?

    registrations << @client.register(name, ":3333")
    sleep(0.5)
    assert !standby.elected?

    registrations.each(&:unregister)
    sleep(0.5)
    assert standby.elected?
  end
end

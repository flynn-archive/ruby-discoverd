require "test_helper"

class TestClient < Minitest::Test
  def setup
    @rpc_client_class = RPCPlus.send(:remove_const, :Client)
    RPCPlus.send(:const_set, :Client, Minitest::Mock.new)
  end

  def teardown
    RPCPlus.send(:remove_const, :Client)
    RPCPlus.send(:const_set, :Client, @rpc_client_class)
  end

  def test_explicit_address
    address = "1.2.3.4:5678"
    RPCPlus::Client.expect :new, nil, ["1.2.3.4", 5678]
    Discover::Client.new(address)
  end

  def test_explicit_address_as_uri
    address = "tcp://1.2.3.4:5678"
    RPCPlus::Client.expect :new, nil, ["1.2.3.4", 5678]
    Discover::Client.new(address)
  end

  def test_address_as_environment_variable
    ENV["DISCOVERD"] = "tcp://5.6.7.8:4321"
    RPCPlus::Client.expect :new, nil, ["5.6.7.8", 4321]
    Discover::Client.new
    ENV.delete "DISCOVERD"
  end

  def test_default_address
    RPCPlus::Client.expect :new, nil, ["127.0.0.1", 1111]
    Discover::Client.new
  end
end

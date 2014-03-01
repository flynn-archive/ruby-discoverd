require "securerandom"

class DiscoverIntegrationTest < Minitest::Test
  EXTERNAL_IP = "1.2.3.4"

  def setup
    etcd_name = SecureRandom.hex
    @etcd_pid = spawn("etcd -name #{etcd_name}", [:out, :err] => "/dev/null")
    sleep(0.2)

    @discoverd_pid = spawn({ "EXTERNAL_IP" => EXTERNAL_IP }, "discoverd", [:out, :err] => "/dev/null")
    sleep(0.2)

    @client = Discover::Client.new
  end

  def teardown
    @client.unregister_all
    sleep(0.2)
    Process.kill("TERM", @discoverd_pid)
    Process.kill("TERM", @etcd_pid)
    Process.waitall
  end
end

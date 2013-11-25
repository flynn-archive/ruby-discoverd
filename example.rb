client = Discover::Client.new

client.register("name", 1111, "127.0.0.1")

service = client.service("foo")
service.online
service.addrs

service.each_event do |update|

end

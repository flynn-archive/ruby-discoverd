require 'discover/version'
require 'celluloid/io'
require 'yajl'

module Discover
  class Client
    def initialize(host='127.0.0.1', port=1111)
      @client = RPCClient.new(host, port)
    end

    def service(name)
      Service.new(@client, name)
    end

    def register(name, port=nil, ip=nil)
      args = {
        "Name" => name,
        "Addr" => "#{ip}:#{port}"
      }

      @client.request('Agent.Register', args)

      # spawn heartbeat actor
      # return Discover::Registration
    end
  end

  class Response
    attr_reader :value

    def initialize(res)
      @value = res
    end
  end

  class RPCClient
    include Celluloid::IO
    finalizer :shutdown

    def initialize(host, port)
      @seq = 0
      @requests = {}

      @sock = Celluloid::IO::TCPSocket.new(host, port)
      @sock.write("CONNECT /_goRPC_ HTTP/1.0\r\nAccept: application/vnd.flynn.rpc-hijack+json\r\n\r\n")
      response = @sock.readline(/\r?\n/)
      raise 'invalid response' if !response.start_with?('HTTP/1.0 200')
      @sock.readline(/\r?\n/)
      async.read_responses
    end

    def request(method, arg, &block)
      req = { 'id' => @seq+=1, 'method' => method, 'params' => [arg] }
      future = Celluloid::Future.new
      @requests[req['id']] = { stream: block, future: future }
      Yajl::Encoder.encode(req, @sock)

      # block until stream is done, so that the block doesn't become invalid due
      # to https://github.com/celluloid/celluloid/pull/245
      future.value if block

      future
    end

    private

    def shutdown
      @sock.close if @sock
    end

    def read_responses
      loop do
        response = Yajl::Parser.parse(@sock.readline)
        req = @requests[response['id']]
        next if !req
        if req[:stream] && !response['error']
          req[:stream].call(response['result'])
          next
        end
        req[:future].signal(Response.new(response))
        @requests.delete(response['id'])
      end
    end
  end

  class Service
    include Celluloid

    class Update < Struct.new(:address, :name, :online)
      def self.from_hash(hash)
        new *hash.values_at("Addr", "Name", "Online")
      end

      def online?
        online == true
      end

      def offline?
        !online?
      end

      # The sentinel update marks the end of existing updates from discoverd
      def sentinel?
        address.empty? && name.empty?
      end
    end

    def initialize(client, name)
      @client = client
      @name = name
      @current = Condition.new
      @instances = {}
      async.process_updates
    end

    def online
      @current.wait if @current
      @instances.values.select(&:online?)
    end

    def offline
      @current.wait if @current
      @instances.values.select(&:offline?)
    end

    def each_update(&block)
      # add to actor subscription list
    end

    private

    def process_updates
      @client.request('Agent.Subscribe', {'Name' => @name}) do |update|
        update = Update.from_hash(update)

        if @current && update.sentinel?
          c, @current = @current, nil
          c.broadcast
        end

        @instances[update.address] = update
      end
      # TODO: handle disconnect
    end
  end

  class Registration
    def destroy
    end
  end
end

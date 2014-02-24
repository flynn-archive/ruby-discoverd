require 'discover/version'
require 'celluloid/io'
require 'yajl'

module Discover
  class Client
    include Celluloid

    def initialize(host='127.0.0.1', port=1111)
      @client        = RPCClient.new(host, port)
      @registrations = []
    end

    def request(*args, &block)
      @client.request(*args, &block)
    end

    def service(name, filters={})
      Service.new(self, name, filters)
    end

    def register(name, port=nil, ip=nil, attributes={})
      _register(name, port, ip, attributes, false)
    end

    def register_and_standby(name, port=nil, ip=nil, attributes={})
      _register(name, port, ip, attributes, true)
    end

    def remove_registration(reg)
      @registrations.delete(reg)
    end

    def unregister_all
      @registrations.each(&:unregister)
    end

    private
    def _register(name, port=nil, ip=nil, attributes={}, standby=false)
      reg = Registration.new(self, name, "#{ip}:#{port}", attributes, standby)
      @registrations << reg
      reg.register
      reg
    end
  end

  class Registration
    include Celluloid

    HEARTBEAT_INTERVAL = 5

    def initialize(client, name, address, attributes = {}, standby = false)
      @client     = client
      @name       = name
      @address    = address
      @attributes = attributes
      @standby    = standby
    end

    def register
      send_register_request
      start_heartbeat
      wait_for_election if @standby
    end

    def unregister
      stop_heartbeat
      send_unregister_request
      @client.remove_registration(self)
    end

    def send_register_request
      args = {
        "Name"  => @name,
        "Addr"  => @address,
        "Attrs" => @attributes
      }

      @client.request("Agent.Register", args).value
    end

    def send_unregister_request
      args = {
        "Name"  => @name,
        "Addr"  => @address
      }

      @client.request("Agent.Unregister", args).value
    end

    def start_heartbeat
      @heartbeat = every(HEARTBEAT_INTERVAL) do
        @client.request(
          "Agent.Heartbeat",
          "Name" => @name,
          "Addr" => @address
        )
      end
    end

    def stop_heartbeat
      @heartbeat.cancel
    end

    def wait_for_election
      async.watch_leaders
      wait :elected
    end

    def watch_leaders
      @client.service(@name).each_leader do |leader|
        if leader.address == @address
          signal :elected
        end
      end
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

    class Update < Struct.new(:address, :attributes, :created, :name, :online)
      def self.from_hash(hash)
        new *hash.values_at("Addr", "Attrs", "Created", "Name", "Online")
      end

      def attributes
        super || {}
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

    class Watcher
      include Celluloid

      def initialize(block)
        @block     = block
        @condition = Condition.new
      end

      def notify(update)
        @block.call update
      end

      def done
        @condition.broadcast
      end

      def wait
        @condition.wait
      end
    end

    def initialize(client, name, filters={})
      @client = client
      @name = name
      @filters = filters
      @current = Condition.new
      @instances = {}
      @watchers = []
      async.process_updates
    end

    def online
      @current.wait if @current
      @instances.values
    end

    def leader
      online.sort_by(&:created).first
    end

    def each_leader(&block)
      leader = self.leader
      block.call leader if leader

      each_update(false) do |update|
        if leader.nil? || (update.offline? && leader && update.address == leader.address)
          leader = self.leader
          block.call leader if leader
        end
      end
    end

    def each_update(include_current = true, &block)
      # Since updates are coming from a Proc being called in a different
      # Actor (the RPCClient), we need to suspend update notifications
      # here to avoid race conditions where we could potentially miss
      # updates between initializing the Watcher and adding it to @watchers
      watcher = pause_updates do
        watcher = Watcher.new(block)

        if include_current
          online.each { |u| watcher.notify u }
        end

        @watchers << watcher

        watcher
      end

      watcher.wait
    end

    private

    def process_updates
      @client.request('Agent.Subscribe', {'Name' => @name}) do |update|
        update = Update.from_hash(update)

        if @current && update.sentinel?
          c, @current = @current, nil
          c.broadcast
          next
        end

        if matches_filters?(update)
          if update.online?
            @instances[update.address] = update
          else
            @instances.delete(update.address)
          end

          @pause_updates.wait if @pause_updates
          @watchers.each { |w| w.notify update }
        end
      end
      @watchers.each(&:done)
      # TODO: handle disconnect
    end

    def matches_filters?(update)
      @filters.all? do |key, val|
        update.attributes[key] == val
      end
    end

    def pause_updates(&block)
      @pause_updates = Condition.new

      result = block.call

      c, @pause_updates = @pause_updates, nil
      c.broadcast

      result
    end
  end
end

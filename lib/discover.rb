require "uri"
require "rpcplus"

module Discover
  class Client
    include Celluloid

    def initialize(address = nil)
      uri = parse(address || ENV["DISCOVERD"] || "127.0.0.1:1111")

      @client        = RPCPlus::Client.new(uri.host, uri.port)
      @registrations = {}
    end

    def request(*args, &block)
      @client.request(*args, &block)
    end

    def service(name, filters={})
      Service.new(self, name, filters)
    end

    def register(name, address, attributes={})
      _register(name, address, attributes, false)
    end

    def register_and_standby(name, address, attributes={})
      _register(name, address, attributes, true)
    end

    def remove_registration(address)
      @registrations.delete(address)
    end

    def unregister_all
      @registrations.values.each(&:unregister)
    end

    private
    def parse(address)
      URI.parse(address)
    rescue URI::InvalidURIError
      URI.parse("tcp://#{address}")
    end

    def _register(name, address, attributes={}, standby=false)
      Registration.new(self, name, address, attributes, standby).tap do |reg|
        reg.register

        # Remove any existing registration for the full address
        if old_reg = remove_registration(reg.full_address)
          old_reg.stop_heartbeat
        end

        @registrations[reg.full_address] = reg
      end
    end
  end

  class Registration
    include Celluloid

    HEARTBEAT_INTERVAL = 5

    attr_reader :full_address

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
      @client.remove_registration(@full_address)
    end

    def send_register_request
      args = {
        "Name"  => @name,
        "Addr"  => @address,
        "Attrs" => @attributes
      }

      @full_address = @client.request("Agent.Register", args).value
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
          "Agent.Register",
          "Name"  => @name,
          "Addr"  => @address,
          "Attrs" => @attributes
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
        if @full_address && leader.address == @full_address
          signal :elected
        end
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

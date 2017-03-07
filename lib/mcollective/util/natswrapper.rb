require "nats/io/client"

module MCollective
  module Util
    # A wrapper class around the Pure Ruby NATS gem
    #
    # MCollective has some non compatible expectations about how
    # message flow works such as having a blocking receive and publish
    # method it calls when it likes, while typical flow is to pass
    # a block and then callbacks will be called.
    #
    # This wrapper bridges the 2 worlds using ruby Queues to simulate the
    # blocking receive expectation MCollective has thanks to its initial
    # design around the Stomp gem.
    class NatsWrapper
      attr_reader :subscriptions, :received_queue

      def initialize
        @received_queue = Queue.new
        @subscriptions = {}
        @subscription_mutex = Mutex.new
        @started = false
        @client = NATS::IO::Client.new
      end

      # Has the NATS connection started
      #
      # @return [Boolean]
      def started?
        @started
      end

      # Is there a NATS client created
      #
      # @return [Boolean]
      def has_client?
        !!@client
      end

      # Retrieves the current connected server
      #
      # @return [String,nil]
      def connected_server
        return nil unless connected?

        @client.connected_server
      end

      # Connection stats from the NATS gem
      #
      # @return [Hash]
      def stats
        return {} unless has_client?

        @client.stats
      end

      # Client library flavour
      #
      # @return [String]
      def client_flavour
        "nats-pure"
      end

      # Client library version
      #
      # @return [String]
      def client_version
        NATS::IO::VERSION
      end

      # Connection options from the NATS gem
      #
      # @return [Hash]
      def active_options
        return {} unless has_client?

        @client.options
      end

      # Is NATS connected
      #
      # @return [Boolean]
      def connected?
        has_client? && @client.connected?
      end

      # Does a backoff sleep up to 2 seconds
      #
      # @return [void]
      def backoff_sleep
        @backoffcount ||= 1

        if @backoffcount >= 50
          sleep(2)
        else
          sleep(0.04 * @backoffcount)
        end

        @backoffcount += 1
      end

      # Logs the NATS server pool for nats-pure
      #
      # The current server pool is dynamic as the NATS servers can announce
      # new cluster members as they join the pool, little helper for logging
      # the pool on major events
      #
      # @return [void]
      def log_nats_pool
        return unless has_client?

        servers = @client.server_pool.map do |server|
          server[:uri].to_s
        end

        Log.info("Current server pool: %s" % servers.join(", "))
      end

      # Starts the EM based NATS connection
      #
      # @param options [Hash] Options as per {#NATS.start}
      def start(options={})
        # Client connects pretty much soon as it's initialized which is very early
        # and some applications like 'request_cert' just doesnt need/want a client
        # since for example there won't be SSL stuff yet, so if a application calls
        # disconnect very early on this should avoid that chicken and egg
        return if @force_Stop

        @client.on_reconnect do
          Log.warn("Reconnected after connection failure: %s" % @client.connected_server)
          log_nats_pool
          @backoffcount = 1
        end

        @client.on_disconnect do |error|
          if error
            Log.warn("Disconnected from NATS: %s: %s" % [error.class, error.to_s])
          else
            Log.info("Disconnected from NATS for an unknown reason")
          end
        end

        @client.on_error do |error|
          Log.error("Error in NATS connection: %s: %s" % [error.class, error.to_s])
        end

        @client.on_close do
          Log.info("Connection to NATS server closed")
        end

        begin
          @client.connect(options)
        rescue
          Log.error("Error during initial NATS setup: %s: %s" % [$!.class, $!.message])
          Log.debug($!.backtrace.join("\n\t"))

          sleep 1

          Log.error("Retrying NATS initial setup")

          retry
        end

        sleep(0.01) until connected?

        @started = true

        nil
      end

      # Stops the NATS connection
      def stop
        @force_stop = true
        @client.close
      end

      # Receives a message from the receive queue
      #
      # This will block until a message is available
      #
      # @return [String] received message
      def receive
        @received_queue.pop
      end

      # Public a message
      #
      # @param destination [String] the NATS destination
      # @param payload [String] the string to publish
      # @param reply [String] a reply destination
      def publish(destination, payload, reply=nil)
        server_state = "%s %s" % [connected? ? "connected" : "disconnected", @client.connected_server]

        if reply
          Log.debug("Publishing to %s reply to %s via %s" % [destination, reply, server_state])
        else
          Log.debug("Publishing to %s via %s" % [destination, server_state])
        end

        @client.publish(destination, payload, reply)
      end

      # Subscribes to a message source
      #
      # @param source_name [String]
      def subscribe(source_name)
        @subscription_mutex.synchronize do
          Log.debug("Subscribing to %s" % source_name)

          unless @subscriptions.include?(source_name)
            @subscriptions[source_name] = @client.subscribe(source_name) do |msg, _, sub|
              Log.debug("Received a message on %s" % [sub])
              @received_queue << msg
            end
          end
        end
      end

      # Unsubscribes from a message source
      #
      # @param source_name [String]
      def unsubscribe(source_name)
        @subscription_mutex.synchronize do
          if @subscriptions.include?(source_name)
            @client.unsubscribe(@subscriptions[source_name])
            @subscriptions.delete(source_name)
          end
        end
      end

      # Test helper
      #
      # @private
      def stub_client(client)
        @client = client
      end
    end
  end
end

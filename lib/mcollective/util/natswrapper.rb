require "nats/client"

module MCollective
  module Util
    # A wrapper class around the EM based NATS gem
    #
    # MCollective has some non EM compatible expectations about how
    # message flow works such as having a blocking receive and publish
    # method it calls when it likes, while typical EM flow is to pass
    # a block and then callbacks will be called.
    #
    # This wrapper bridges the 2 worlds using ruby Queues to simulate the
    # blocking receive expectation MCollective has thanks to its initial
    # design around the Stomp gem.
    #
    # The EM code is run in a Thread and all EM stuff is done there, this will
    # hopefully sufficiently isolate the competing threading models.
    class NatsWrapper
      attr_reader :subscriptions, :received_queue

      def initialize
        @received_queue = Queue.new
        @subscriptions = {}
        @subscription_mutex = Mutex.new
        @started = false
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
        !!NATS.client
      end

      # Is NATS connected
      #
      # @return [Boolean]
      def connected?
        has_client? && NATS.connected?
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

      # Starts the EM based NATS connection
      #
      # @param options [Hash] Options as per {#NATS.start}
      def start(options={})
        @started = true
        @nats = nil

        @em_thread = Thread.new do
          begin
            NATS.on_error do |e|
              Log.error("Error in NATS connection: %s: %s" % [e.class, e.to_s])

              backoff_sleep

              raise(e)
            end

            NATS.start(options) do |c|
              Log.info("NATS is connected to %s" % c.connected_server)

              c.on_reconnect do |connection|
                Log.info("Reconnected after connection failure: %s" % connection.connected_server)
                @backoffcount = 1
              end

              c.on_disconnect do |reason|
                Log.info("Disconnected from NATS: %s" % reason)
              end

              c.on_close do
                Log.info("Connection to NATS server closed")
              end
            end

            sleep(0.01) until has_client?
          rescue
            Log.error("Error during initial NATS setup: %s: %s" % [$!.class, $!.message])
            Log.debug($!.backtrace.join("\n\t"))

            sleep 1

            Log.error("Retrying NATS initial setup")

            retry
          end
        end

        sleep(0.01) until connected?
      end

      # Stops the NATS connection
      def stop
        NATS.stop
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
        server_state = "%s %s" % [NATS.connected? ? "connected" : "disconnected", NATS.connected_server]

        if reply
          Log.debug("Publishing to %s reply to %s via %s" % [destination, reply, server_state])
        else
          Log.debug("Publishing to %s via %s" % [destination, server_state])
        end

        NATS.publish(destination, payload, reply)
      end

      # Subscribes to a message source
      #
      # @param source [String]
      def subscribe(source_name)
        @subscription_mutex.synchronize do
          Log.debug("Subscribing to %s" % source_name)

          unless @subscriptions.include?(source_name)
            @subscriptions[source_name] = NATS.subscribe(source_name) do |msg, _, sub|
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
            NATS.unsubscribe(@subscriptions[source_name])
            @subscriptions.delete(source_name)
          end
        end
      end
    end
  end
end

module MCollective
  module Util
    class FederationBroker
      class Base
        # @private
        attr_reader :connection, :choria, :config

        # @param broker [FederationBroker]
        # @param inbox [Queue] connection from the other Processor
        # @param outbox [Queue] connection to the other Processor
        # @return [Base]
        def initialize(broker, inbox=nil, outbox=nil)
          @broker = broker
          @outbox = outbox
          @inbox = inbox
          @config = Config.instance
          @connection = Util::NatsWrapper.new
          @choria = Choria.new(nil, nil, false)
        end

        def local_stats
          @stats ||= {
            "source" => queue[:name],
            "received" => 0,
            "sent" => 0,
            "last_message" => 0,
            "connected_server" => "disconnected"
          }
        end

        # List of servers to connect to
        #
        # @abstract
        # @return [Array<String>] list of servers in nats://host:port format
        def servers
          raise(NotImplementedError, "%s does not implement the #servers method" % [self.class])
        end

        # The type of processor this is
        #
        # @abstract
        # @return ["collective", "federation"]
        def processor_type
          raise(NotImplementedError, "%s does not implement the #processor_type method" % [self.class])
        end

        # The queue to connect to
        #
        # @example
        #     {
        #       :name => "choria.production.federation",
        #       :queue => "foo_federation"
        #     }
        #
        # @abstract
        # @return [Hash] with :queue and :name
        def queue
          raise(NotImplementedError, "%s does not implement the #queue method" % [self.class])
        end

        # Processor specific process logic
        #
        # @abstract
        # @param msg [Hash] message from the wire
        def process(msg)
          raise(NotImplementedError, "%s does not implement the #process method" % [self.class])
        end

        # Determines if a message should be processed
        #
        # This should do validity checks, structure tests, security checks against the reply-to etc
        #
        # @abstract
        # @param msg [Hash] the message to test
        # @return [Boolean]
        def should_process?(msg)
          Log.warn("%s did not override should_process?, denying all messages" % [self.class])
          false
        end

        # Processor statistics
        #
        # @return [Hash]
        def stats
          local_stats.merge(
            "work_queue" => @inbox.size,
            "connected_server" => connected_server
          )
        end

        # NATS source for communicating with the Federation
        #
        # @return [String]
        def federation_source_name
          "choria.federation.%s.federation" % cluster_name
        end

        # NATS source for communicating with the collective
        #
        # @return [String]
        def collective_source_name
          "choria.federation.%s.collective" % cluster_name
        end

        # Records self in the seen-by headers
        #
        # @param headers [Hash]
        def record_seen(headers)
          return unless headers.include?("seen-by")

          c_out = processor_type == "federation" ? "collective" : "federation"
          c_in = processor_type

          (headers["seen-by"] ||= []) << [
            @broker.connections[c_in].connected_server.to_s,
            "%s:%s" % [cluster_name, instance_name],
            @broker.connections[c_out].connected_server.to_s
          ]
        end

        # Handled a specific inbox item
        #
        # @param item [Hash] item received from the other processor
        # @raise [StandardError] for invalid items
        def handle_inbox_item(item)
          raise("Invalid item received: not a hash") unless item.is_a?(Hash)
          raise("Invalid item received: :target not an array") unless item[:targets].is_a?(Array)
          raise("Invalid item received: :data not a String") unless item[:data].is_a?(String)

          item[:targets].each do |target|
            local_stats["sent"] += 1
            local_stats["last_message"] = Time.now.to_i

            Log.info("%s publishing %s to %s" % [processor_type.capitalize, item[:req], target])

            begin
              connection.publish(target, item[:data])
            rescue
              @inbox << item
              Log.error("Failed to publish from %s to %s: %s: %s" % [processor_type, item[:target], $!.class, $!.to_s])
              raise
            end
          end
        end

        # Handler for message from the other Processor
        #
        # This will iterate over the Queue and publish any messages the other
        # Processor wants published
        def inbox_handler
          thread = Thread.new do
            begin
              Log.info("Starting inbox handler for %s" % processor_type)

              loop do
                handle_inbox_item(@inbox.pop)
              end
            rescue
              Log.error("%s inbox handler failed: %s: %s" % [processor_type, $!.class, $!.to_s])
              Log.debug($!.join("\t\n"))

              sleep 1

              retry
            end
          end

          @broker.record_thread("%s_inbox_handler" % processor_type, thread)
        end

        # The NATS server that this Processor is connected to
        #
        # @return [String] `disconnected` when not connected
        def connected_server
          connection.connected_server || "disconnected"
        end

        # The instance name of this Cluster member
        #
        # A Federation Broker can have many cluster members, each should
        # ideally have unique names
        #
        # @return [String]
        def instance_name
          @broker.instance_name
        end

        # The Feradtion Broker cluster name
        #
        # This should be unique, any broker with the same cluster name
        # will load share work.  This name is what a user configures in
        # his client config as federation member names
        #
        # @return [String]
        def cluster_name
          @broker.cluster_name
        end

        # Starts the connection and traffic handlers
        def start_connection_and_handlers
          server_list = servers

          Log.info("Starting Federation Broker %s Processor %s#%s against %s" % [processor_type, cluster_name, instance_name, server_list.to_s])

          start_connection(server_list)
          inbox_handler
          consume
        end

        # Starts the NatsWrapper connection
        #
        # @param server_list [Array] list of servers, see {#servers}
        def start_connection(server_list=nil)
          server_list ||= servers

          connection.start(default_nats_parameters.merge(:servers => server_list))
        end

        # Starts the main flow of the particular Processor
        #
        # This starts a middleware handler via {Util::NatsWrapper} and pass any messages received
        # to the {#consume} message.  It also starts the {#inbox_handler}
        #
        # @return [NatsWrapper]
        def start
          thread = Thread.new do
            begin
              start_connection_and_handlers
            rescue
              Log.warn("%s Federation Broker failed: %s: %s" % [processor_type.capitalize, $!.class, $!.to_s])
              Log.debug($!.backtrace.join("\n\t"))

              connection.stop

              sleep 1

              retry
            end
          end

          @broker.record_thread("%s_middleware_handler" % processor_type, thread)

          connection
        end

        # Consumes message from the configured queue and connection
        #
        # This will call the {#process} method for every message received
        # from the middleware
        def consume
          consume_from(queue) do |msg|
            msg = JSON.parse(msg)

            local_stats["received"] += 1
            local_stats["last_message"] = Time.now.to_i

            process(msg) if should_process?(msg)
          end
        end

        # Consumes messages from a specific queue and connection
        #
        # Any message received from the middleware is yielded to the given block
        #
        # @param queue [Hash] as produced by {#queue}
        # @param block [Proc] block to call for every message
        def consume_from(queue, &block)
          Log.info("Starting consuming message from %s" % queue[:name])

          begin
            if queue[:queue]
              connection.subscribe(queue[:name], :queue => queue[:queue])
            else
              connection.subscribe(queue[:name])
            end
          rescue
            Log.warn("Subscribing to %s failed: %s: %s" % [queue[:name], $!.class, $!.to_s])
            Log.debug($!.backtrace.join("\n\t"))
            sleep 1
            retry
          end

          loop do
            begin
              yield(connection.receive)
            rescue
              Log.warn("Failed while processing a message from %s: %s: %s" % [queue[:name], $!.class, $!.to_s])
              Log.debug($!.backtrace.join("\n\t"))
            end
          end
        end

        # Default NATS connection parameters
        #
        # @return [Hash]
        def default_nats_parameters
          {
            :max_reconnect_attempts => -1,
            :reconnect_time_wait => 1,
            :name => "fedbroker_%s_%s" % [cluster_name, instance_name],
            :tls => {
              :context => choria.ssl_context
            }
          }
        end
      end
    end
  end
end

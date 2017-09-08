require "resolv"
require_relative "../util/choria"
require_relative "../util/natswrapper"

module MCollective
  module Connector
    class Nats < Base
      attr_reader :connection

      def initialize
        @config = Config.instance
        @subscriptions = []
        @connection = Util::NatsWrapper.new

        Log.info("Choria NATS.io connector using pure ruby nats/io/client %s with protocol version %s" % [NATS::IO::VERSION, NATS::IO::PROTOCOL])
      end

      # Determines if the NATS connection is active
      #
      # @return [Boolean]
      def connected?
        connection.connected?
      end

      # Current connected server
      #
      # @return [String,nil]
      def connected_server
        connection.connected_server
      end

      # Retrieves the NATS connection stats
      #
      # @return [Hash]
      def stats
        connection.stats
      end

      # Client library version
      #
      # @return [String]
      def client_version
        connection.client_version
      end

      # Client library flavour
      #
      # @return [String]
      def client_flavour
        connection.client_flavour
      end

      # Connection options from the NATS gem
      #
      # @return [Hash]
      def active_options
        connection.active_options
      end

      # Attempts to connect to the middleware, noop when already connected
      #
      # @return [void]
      # @raise [StandardError] when SSL files are not readable
      def connect
        if connection && connection.started?
          Log.debug("Already connection, not re-initializing connection")
          return
        end

        parameters = {
          :max_reconnect_attempts => -1,
          :reconnect_time_wait => 1,
          :dont_randomize_servers => !choria.randomize_middleware_servers?,
          :name => @config.identity,
          :tls => {
            :context => choria.ssl_context
          }
        }

        if $choria_unsafe_disable_nats_tls # rubocop:disable Style/GlobalVars
          Log.warn("Disabling TLS in NATS connector, this is not a production supported setup")
          parameters.delete(:tls)
        end

        servers = server_list

        unless servers.empty?
          Log.debug("Connecting to servers: %s" % servers.join(", "))
          parameters[:servers] = servers
        end

        choria.check_ssl_setup

        connection.start(parameters)

        nil
      end

      # Disconnects from NATS
      def disconnect
        connection.stop
      end

      # Creates the middleware headers needed for a given message
      #
      # @param msg [Message]
      # @return [Hash]
      def headers_for(msg)
        # mc_sender is only passed bacause M::Message incorrectly assumed this is some required
        # part of messages when its just some internals of the stomp based connectors that bled out
        headers = {
          "mc_sender" => @config.identity
        }

        headers["seen-by"] = [] if msg.headers.include?("seen-by")

        if [:request, :direct_request].include?(msg.type)
          if msg.reply_to
            headers["reply-to"] = msg.reply_to
          else
            # if its a request/direct_request style message and its not
            # one we're replying to - ie. its a new message we're making
            # we'll need to set a reply-to target that the daemon will
            # subscribe to
            headers["reply-to"] = make_target(msg.agent, :reply, msg.collective)
          end

          if msg.headers.include?("seen-by")
            headers["seen-by"] << [@config.identity, connected_server.to_s]
          end
        elsif msg.type == :reply
          if msg.request.headers.include?("seen-by")
            headers["seen-by"] = msg.request.headers["seen-by"]
            headers["seen-by"].last << connected_server.to_s
          end
        end

        headers
      end

      # Create a target structure for a message
      #
      # @example data
      #
      #     {
      #       :name => "nats.name",
      #       :headers => { headers... }
      #     }
      #
      # @param msg [Message]
      # @param identity [String,nil] override identity
      # @return [Hash]
      def target_for(msg, identity=nil)
        target = nil

        if msg.type == :reply
          raise("Do not know how to reply, no reply-to header has been set on message %s" % msg.requestid) unless msg.request.headers["reply-to"]

          target = {:name => msg.request.headers["reply-to"], :headers => {}}

        elsif [:request, :direct_request].include?(msg.type)
          target = {:name => make_target(msg.agent, msg.type, msg.collective, identity), :headers => {}}

        else
          raise("Don't now how to create a target for message type %s" % msg.type)

        end

        target[:headers].merge!(headers_for(msg))

        target
      end

      # Retrieves the current process pid
      #
      # @note mainly used for testing
      # @return [Fixnum]
      def current_pid
        $$
      end

      # Creates a target structure
      #
      # @param agent [String] agent name
      # @param type [:directed, :broadcast, :reply, :request, :direct_request]
      # @param collective [String] target collective name
      # @param identity [String,nil] identity for the request, else node configured identity
      # @return [String] target name
      # @raise [StandardError] on invalid input
      def make_target(agent, type, collective, identity=nil)
        raise("Unknown target type %s" % type) unless [:directed, :broadcast, :reply, :request, :direct_request].include?(type)

        raise("Unknown collective '%s' known collectives are '%s'" % [collective, @config.collectives.join(", ")]) unless @config.collectives.include?(collective)

        identity ||= @config.identity

        case type
        when :reply
          "%s.reply.%s.%d.%d" % [collective, identity, current_pid, Client.request_sequence]

        when :broadcast, :request
          "%s.broadcast.agent.%s" % [collective, agent]

        when :direct_request, :directed
          "%s.node.%s" % [collective, identity]
        end
      end

      # Publishes a message to the middleware
      #
      # @param msg [Message]
      def publish(msg)
        msg.base64_encode!

        if choria.federated?
          msg.type == :direct_request ? publish_federated_directed(msg) : publish_federated_broadcast(msg)
        else
          msg.type == :direct_request ? publish_connected_directed(msg) : publish_connected_broadcast(msg)
        end
      end

      # Publish a directed request via a Federation Broker
      #
      # @param msg [Message]
      def publish_federated_directed(msg)
        messages = []
        target = target_for(msg, msg.discovered_hosts[0])

        msg.discovered_hosts.in_groups_of(200) do |nodes|
          node_targets = nodes.compact.map do |node|
            target_for(msg, node)[:name]
          end

          data = {
            "protocol" => "choria:transport:1",
            "data" => msg.payload,
            "headers" => {
              "federation" => {
                "target" => node_targets,
                "req" => msg.requestid
              }
            }.merge(target[:headers])
          }

          messages << JSON.dump(data)
        end

        choria.federation_collectives.each do |network|
          messages.each do |data|
            network_target = "choria.federation.%s.federation" % network

            Log.debug("Sending a federated direct message via NATS target '%s' for message type %s" % [network_target, msg.type])

            connection.publish(network_target, data, target[:headers]["reply-to"])
          end
        end
      end

      # Publish a directed request to a connected collective
      #
      # @param msg [Message]
      def publish_connected_directed(msg)
        msg.discovered_hosts.each do |node|
          target = target_for(msg, node)
          data = {
            "protocol" => "choria:transport:1",
            "data" => msg.payload,
            "headers" => target[:headers]
          }

          Log.debug("Sending a direct message to %s via NATS target '%s' for message type %s" % [node, target.inspect, msg.type])

          connection.publish(target[:name], data.to_json, target[:headers]["reply-to"])
        end
      end

      # Publish a broadcast message to via a Federation Broker
      #
      # @param msg [Message]
      def publish_federated_broadcast(msg)
        target = target_for(msg)
        data = {
          "protocol" => "choria:transport:1",
          "data" => msg.payload,
          "headers" => {
            "federation" => {
              "target" => [target[:name]],
              "req" => msg.requestid
            }
          }.merge(target[:headers])
        }

        data = JSON.dump(data)

        choria.federation_collectives.each do |network|
          target[:name] = "choria.federation.%s.federation" % network

          Log.debug("Sending a federated broadcast message to NATS target '%s' for message type %s" % [target.inspect, msg.type])

          connection.publish(target[:name], data, target[:headers]["reply-to"])
        end
      end

      # Publish a broadcast message to a connected collective
      #
      # @param msg [Message]
      def publish_connected_broadcast(msg)
        target = target_for(msg)
        data = {
          "protocol" => "choria:transport:1",
          "data" => msg.payload,
          "headers" => target[:headers]
        }

        # only happens when replying
        if received_message = msg.request
          if received_message.headers.include?("federation")
            data["headers"]["federation"] = received_message.headers["federation"]
          end
        end

        Log.debug("Sending a broadcast message to NATS target '%s' for message type %s" % [target.inspect, msg.type])

        connection.publish(target[:name], JSON.dump(data), target[:headers]["reply-to"])
      end

      # Unsubscribe from the target for a agent
      #
      # @see make_target
      # @param agent [String] agent name
      # @param type [:reply, :broadcast, :request, :direct_request, :directed] type of message you want a subscription for
      # @param collective [String] the collective to subscribe for
      # @return [void]
      def unsubscribe(agent, type, collective)
        target = make_target(agent, type, collective)
        Log.debug("Unsubscribing from %s" % target)

        connection.unsubscribe(target)
      end

      # Subscribes to the topics/queues needed for a particular agent
      #
      # @see make_target
      # @param agent [String] agent name
      # @param type [:reply, :broadcast, :request, :direct_request, :directed] type of message you want a subscription for
      # @param collective [String] the collective to subscribe for
      # @return [void]
      def subscribe(agent, type, collective)
        target = make_target(agent, type, collective)

        connection.subscribe(target)
      end

      # Receives a message from the middleware
      #
      # @note blocks until one is received
      # @return [Message]
      def receive
        msg = nil

        until msg
          Log.debug("Waiting for a message from NATS")

          received = connection.receive

          begin
            msg = JSON.parse(received)
          rescue
            Log.warn("Got non JSON data from the broker: %s" % [received])
            msg = nil
          end
        end

        if msg["headers"].include?("seen-by")
          msg["headers"]["seen-by"] << [connected_server.to_s, @config.identity]
        end

        Message.new(msg["data"], msg, :base64 => true, :headers => msg["headers"])
      end

      # Retrieves the list of server and port combos to attempt to connect to
      #
      # Configured servers are checked, then SRV records and finally a fall
      # back to puppet:4222 is done
      #
      # @return [Array<String>] list of servers in form of a URI
      def server_list
        uris = choria.middleware_servers("puppet", "4222").map do |host, port|
          URI("nats://%s:%s" % [host, port])
        end

        decorate_servers_with_users(uris).map(&:to_s)
      end

      # Add user and pass to a series of URIs
      #
      # @param servers [Array<URI>] list of URI's to decorate
      # @return [Array<URI>]
      def decorate_servers_with_users(servers)
        user = get_option("nats.user", environment["MCOLLECTIVE_NATS_USERNAME"])
        pass = get_option("nats.pass", environment["MCOLLECTIVE_NATS_PASSWORD"])

        if user && pass
          servers.each do |uri|
            uri.user = user
            uri.password = pass
          end
        end

        servers
      end

      # Retrieves the environment, mainly used for testing
      def environment
        ENV
      end

      # Gets a config option
      #
      # @param opt [String] config option to look up
      # @param default [Object] default to return when not found
      # @return [Object] the found data or default
      # @raise [StandardError] when no default is given and option is not found
      def get_option(opt, default=:_unset)
        return @config.pluginconf[opt] if @config.pluginconf.include?(opt)
        return default unless default == :_unset

        raise("No plugin.%s configuration option given" % opt)
      end

      def choria
        @_choria ||= Util::Choria.new("production", nil, false)
      end
    end
  end
end

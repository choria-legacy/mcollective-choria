require_relative "base"

module MCollective
  module Util
    class FederationBroker
      class FederationProcessor < Base
        # @see Base#servers
        def servers
          servers = @choria.federation_middleware_servers

          raise("Could not find any federation middleware servers in configuration or SRV records") unless servers

          servers.map do |host, port|
            URI("nats://%s:%s" % [host, port])
          end.map(&:to_s)
        end

        # @see Base#processor_type
        def processor_type
          "federation"
        end

        # @see Base#queue
        def queue
          {
            :name => federation_source_name,
            :queue => "%s_federation" % cluster_name
          }
        end

        # @see Base#should_process?
        def should_process?(msg)
          unless msg.is_a?(Hash)
            Log.warn("Received a non hash message, cannot process: %s" % [msg.inspect])
            return false
          end

          unless headers = msg["headers"]
            Log.warn("Received a message without headers, cannot process: %s" % [msg.inspect])
            return false
          end

          unless federation = headers["federation"]
            Log.warn("Received an unfederated message, cannot process: %s" % [msg.inspect])
            return false
          end

          reply_to = headers["reply-to"]

          unless reply_to.is_a?(String)
            Log.warn("Received an invalid reply to header:, cannot process: %s" % [msg.inspect])
            return false
          end

          # All reply-to should match NATS topics actually used to receive replies from agents or nodes else someone
          # might abuse this to bridge into other collectives or federations see {Connector::Nats#make_target}
          unless reply_to =~ /^.+?\.reply\./
            Log.warn("Received an invalid reply to target '%s', cannot process: %s" % [reply_to, msg.inspect])
            return false
          end

          # All targets should match NATS topics actually used to talk to agents or nodes else someone
          # might abuse this to bridge into other collectives or federations see {Connector::Nats#make_target}
          federation["target"].each do |target|
            unless target =~ /^.+?\.((broadcast\.agent)|(node))\./
              Log.warn("Received an unexpected remote target '%s', cannot process: %s" % [target, msg.inspect])
              return false
            end
          end

          true
        end

        # Processor specific process logic
        #
        # This received a message from the Collective and converts it into a message that will be
        # published to the Federation, stores the outgoing message in the outbox queue
        #
        # @param (see Base#process)
        def process(msg)
          headers = msg["headers"]
          federation = headers["federation"]

          Log.info("Federation received %s from %s" % [federation["req"], headers["mc_sender"]])

          federation["reply-to"] = headers.delete("reply-to")
          headers["reply-to"] = collective_source_name

          record_seen(headers)

          Log.debug("federation => collective: %s" % [headers])

          @outbox << {
            :targets => federation.delete("target"),
            :req => federation["req"],
            :data => JSON.dump(msg)
          }
        end
      end
    end
  end
end

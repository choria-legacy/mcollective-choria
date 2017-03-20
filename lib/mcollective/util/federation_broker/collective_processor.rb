require_relative "base"

module MCollective
  module Util
    class FederationBroker
      class CollectiveProcessor < Base
        # @see Base#servers
        def servers
          choria.middleware_servers("puppet", "4222").map do |host, port|
            URI("nats://%s:%s" % [host, port])
          end.map(&:to_s)
        end

        # @see Base#processor_type
        def processor_type
          "collective"
        end

        # @see Base#queue
        def queue
          {
            :name => collective_source_name,
            :queue => "%s_collective" % cluster_name
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

          reply_to = federation["reply-to"]

          unless reply_to.is_a?(String)
            Log.warn("Received an invalid reply to header in the federation structure:, cannot process: %s" % [msg.inspect])
            return false
          end

          # All reply-to should match NATS topics actually used to receive replies from agents or nodes else someone
          # might abuse this to bridge into other collectives or federations see {Connector::Nats#make_target}
          unless reply_to =~ /^.+?\.reply\./
            Log.warn("Received a collective message with an unexpected reply to target '%s', cannot process: %s" % [reply_to, msg.inspect])
            return false
          end

          true
        end

        # Processor specific process logic
        #
        # This received a message from the Federation and converts it into a message that will be
        # published to the collective, stores the outgoing message in the outbox queue
        #
        # @param (see Base#process)
        def process(msg)
          headers = msg["headers"]
          federation = headers["federation"]
          reply_to = federation.delete("reply-to")

          Log.info("Collective received %s from %s" % [federation["req"], headers["mc_sender"]])

          record_seen(headers)

          Log.debug("collective => federation: %s" % [headers])

          @outbox << {
            :targets => [reply_to],
            :req => federation["req"],
            :data => JSON.dump(msg)
          }
        end
      end
    end
  end
end

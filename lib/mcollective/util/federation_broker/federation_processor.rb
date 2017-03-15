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

        # Processor specific process logic
        #
        # This received a message from the Collective and converts it into a message that will be
        # published to the Federation, stores the outgoing message in the outbox queue
        #
        # @param (see Base#process)
        def process(msg)
          headers = msg["headers"]

          raise("Received an invalid message, cannot process: %s" % [msg.inspect]) unless headers

          federation = headers["federation"]

          raise("Received an unfederated message, cannot process: %s" % [msg["headers"].inspect]) unless federation

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

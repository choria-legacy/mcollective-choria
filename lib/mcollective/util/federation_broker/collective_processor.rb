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

        # Processor specific process logic
        #
        # This received a message from the Federation and converts it into a message that will be
        # published to the collective, stores the outgoing message in the outbox queue
        #
        # @param (see Base#process)
        def process(msg)
          headers = msg["headers"]
          raise("Collective received an invalid message, cannot process: %s" % [msg]) unless headers

          federation = headers["federation"]
          raise("Collective received an unfederated message, cannot process: %s" % [msg["headers"]]) unless federation

          Log.info("Collective received %s from %s" % [federation["req"], headers["mc_sender"]])

          reply_to = federation.delete("reply-to")

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

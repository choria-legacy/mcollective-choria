require "mcollective/util/choria"

module MCollective
  module Util
    class Playbook
      class Nodes
        class PqlNodes
          def initialize
            @query = nil
          end

          def prepare; end

          def validate_configuration!
            raise("No PQL query specified") unless @query
          end

          def choria
            @_choria ||= Util::Choria.new("production", nil, false)
          end

          # Initialize the nodes source from a hash
          #
          # @param data [Hash] input data matching nodes.json schema
          # @return [PqlNodes]
          def from_hash(data)
            @query = data["query"]

            self
          end

          # Performs the PQL query and extracts certnames
          def discover
            choria.pql_query(@query, true)
          end
        end
      end
    end
  end
end

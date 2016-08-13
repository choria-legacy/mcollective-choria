module MCollective
  module Util
    class Choria
      class Playbook
        class Metadata
          attr_reader :metadata

          def initialize(playbook)
            @playbook = playbook
          end

          def value(item)
            @metadata[item]
          end

          def from_source(metadata)
            @metadata = metadata
          end
        end
      end
    end
  end
end

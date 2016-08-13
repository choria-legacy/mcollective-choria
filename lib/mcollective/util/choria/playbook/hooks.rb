module MCollective
  module Util
    class Choria
      class Playbook
        class Hooks
          attr_reader :hooks

          def initialize(playbook)
            @hooks = []
          end

          def from_source(hooks)
            @hooks = hooks
          end
        end
      end
    end
  end
end

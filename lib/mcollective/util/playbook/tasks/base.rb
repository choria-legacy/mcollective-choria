module MCollective
  module Util
    class Playbook
      class Tasks
        class Base
          attr_accessor :description
          attr_writer :fail_ok

          include TemplateUtil

          def initialize(playbook)
            @playbook = playbook
            @fail_ok = false

            startup_hook
          end

          def startup_hook; end

          def to_s
            "#<%s description: %s>" % [self.class, t(description)]
          end

          def run_task(result)
            validate_configuration!

            result.timed_run(self)
          end

          def run
            raise(StandardError, "run not implemented", caller)
          end

          def validate_configuration!
            raise(StandardError, "validate_configuration! not implemented", caller)
          end

          def from_hash(properties)
            raise(StandardError, "from_hash not implemented", caller)
          end
        end
      end
    end
  end
end

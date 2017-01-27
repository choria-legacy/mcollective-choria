module MCollective
  module Util
    class Playbook
      class DataStores
        class Base
          def initialize(name, playbook)
            @playbook = playbook
            @name = name

            startup_hook
          end

          def startup_hook; end

          def prepare; end

          def from_hash(properties)
            @properties = properties
            self
          end

          def release(key)
            raise(NotImplementedError, "release not implemented in %s" % [self.class], caller)
          end

          def lock(key, timeout)
            raise(NotImplementedError, "lock not implemented in %s" % [self.class], caller)
          end

          def members(key)
            raise(NotImplementedError, "members not implemented in %s" % [self.class], caller)
          end

          def delete(key)
            raise(NotImplementedError, "delete not implemented in %s" % [self.class], caller)
          end

          def write(key, value)
            raise(NotImplementedError, "write not implemented in %s" % [self.class], caller)
          end

          def read(key)
            raise(NotImplementedError, "read not implemented in %s" % [self.class], caller)
          end
        end
      end
    end
  end
end

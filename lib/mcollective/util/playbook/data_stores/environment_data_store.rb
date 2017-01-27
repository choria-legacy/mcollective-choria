require_relative "base"

module MCollective
  module Util
    class Playbook
      class DataStores
        class EnvironmentDataStore < Base
          def read(key)
            raise("No such environment variable %s" % [key_for(key)]) unless include?(key)

            ENV[key_for(key)]
          end

          def write(key, value)
            ENV[key_for(key)] = value
          end

          def delete(key)
            ENV.delete(key_for(key))
          end

          def key_for(key)
            "%s%s" % [@properties["prefix"], key]
          end

          def include?(key)
            ENV.include?(key_for(key))
          end
        end
      end
    end
  end
end

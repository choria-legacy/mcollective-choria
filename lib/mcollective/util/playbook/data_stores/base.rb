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

          # Start up processing
          #
          # Implementations should not create a {initialize} instead they should
          # have this hook which will be called once initialization is done
          def startup_hook; end

          # Prepares the store for use
          #
          # Here you can do things like connect to data bases, set up pools etc
          def prepare; end

          # Validate store properties created using from_hash
          #
          # @raise [StandardError] when configuration is invalid
          def validate_configuration!; end

          # Parse the data store properties as supplied by the playbook
          #
          # @param properties [Hash] lock properties
          # @return [Base]
          def from_hash(properties)
            @properties = properties

            validate_configuration!

            self
          end

          # Release a lock found in the store
          #
          # @note when the lock does not exist it should not raise an error
          # @param key [String] the lock name
          # @raize [StandardError] when releaging fails
          def release(key)
            raise(NotImplementedError, "release not implemented in %s" % [self.class], caller)
          end

          # Locks a specific lock in the store
          #
          # @note when the lock does not exist it should be created
          # @param key [String] the lock name
          # @param timeout [Integer,Float] how long to attempt to get the lock for
          # @param ttl [Integer,Float] after this long the lock should expire in the event that we died
          # @raise [StandardError] when locking fails
          def lock(key, timeout, ttl)
            raise(NotImplementedError, "lock not implemented in %s" % [self.class], caller)
          end

          # Finds the members in a service
          #
          # @param key [String] the service name
          # @return [Array<String>] list of service members
          # @raise [StandardError] when the service is unknown or general error happened
          def members(key)
            raise(NotImplementedError, "members not implemented in %s" % [self.class], caller)
          end

          # Deletes a key from a data store
          #
          # @note deleting non existing data should not raise an error
          # @param key [String] the key to delete
          # @raise [StandardError] when deleting fails
          def delete(key)
            raise(NotImplementedError, "delete not implemented in %s" % [self.class], caller)
          end

          # Writes a value to the key in a data store
          #
          # @param key [String] the key to write
          # @param value [String] the value to write
          # @raise [StandardError] when writing fails
          def write(key, value)
            raise(NotImplementedError, "write not implemented in %s" % [self.class], caller)
          end

          # Reads a key from a data store
          #
          # @param key [String] the key to read
          # @return [String] string found in the data store
          # @raise [StandardError] when the key does not exist
          def read(key)
            raise(NotImplementedError, "read not implemented in %s" % [self.class], caller)
          end
        end
      end
    end
  end
end

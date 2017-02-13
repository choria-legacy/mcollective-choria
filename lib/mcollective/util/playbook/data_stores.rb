require_relative "data_stores/base"
require_relative "data_stores/consul_data_store"
require_relative "data_stores/environment_data_store"
require_relative "data_stores/file_data_store"
require_relative "data_stores/memory_data_store"
require_relative "data_stores/shell_data_store"

module MCollective
  module Util
    class Playbook
      class DataStores
        def initialize(playbook)
          @playbook = playbook
          @stores = {}
        end

        # Determines if a path is in the valid form and a known store
        #
        # @param path [String] example data_store/key_name
        # @return [Boolean]
        def valid_path?(path)
          store, _ = parse_path(path)
          include?(store)
        rescue
          false
        end

        # Parse a normal format data path
        #
        # @param path [String] example data_store/key_name
        # @return [String, String] store name and key name
        # @raise [StandardError] for incorrectly formatted paths
        def parse_path(path)
          if path =~ /^([a-zA-Z0-9\-\_]+)\/(.+)$/
            [$1, $2]
          else
            raise("Invalid data store path %s" % [path])
          end
        end

        # Reads from a path
        #
        # @param path [String] example data_store/key_name
        # @return [Object] data from the data store
        # @raise [StandardError] when reading from the key fails
        # @raise [StandardError] for unknown stores
        def read(path)
          store, key = parse_path(path)

          Log.debug("Reading key %s from data store %s" % [key, store])

          self[store].read(key)
        rescue
          raise("Could not read key %s: %s: %s" % [path, $!.class, $!.to_s])
        end

        # Writes to a path
        #
        # @param path [String] example data_store/key_name
        # @param value [Object] data to write to the path
        # @raise [StandardError] when reading from the key fails
        # @raise [StandardError] for unknown stores
        def write(path, value)
          store, key = parse_path(path)

          Log.debug("Storing data in key %s within data store %s" % [key, store])
          self[store].write(key, value)
        end

        # Deletes a path
        #
        # @param path [String] example data_store/key_name
        # @raise [StandardError] when reading from the key fails
        # @raise [StandardError] for unknown stores
        def delete(path)
          store, key = parse_path(path)

          Log.debug("Deleting key %s from data store %s" % [key, store])
          self[store].delete(key)
        end

        # Members registered in a service
        #
        # @param path [String] example data_store/key_name
        # @return [Array<String>]
        # @raise [StandardError] when reading from the key fails
        # @raise [StandardError] for unknown stores
        def members(path)
          store, service = parse_path(path)

          Log.debug("Retrieving service members for service %s from data store %s" % [service, store])
          self[store].members(service)
        end

        # Attempts to lock a named semaphore, waits until it succeeds
        #
        # @param path [String] example data_store/key_name
        # @raise [StandardError] when obtaining a lock fails
        # @raise [StandardError] when obtaining a lock timesout
        # @raise [StandardError] for unknown stores
        def lock(path)
          store, key = parse_path(path)
          timeout = lock_timeout(store)

          Log.debug("Obtaining lock %s on data store %s with timeout %d" % [key, store, timeout])

          self[store].lock(key, timeout)
        end

        # Attempts to unlock a named semaphore
        #
        # @param path [String] example data_store/key_name
        # @raise [StandardError] when reading from the key fails
        # @raise [StandardError] for unknown stores
        def release(path)
          store, key = parse_path(path)

          Log.debug("Releasing lock %s on data store %s" % [key, store])

          self[store].release(key)
        end

        # Retrieves the configured lock timeout for a store
        #
        # @param store [String]
        # @return [Integer]
        def lock_timeout(store)
          raise("Unknown data store %s" % store) unless include?(store)

          @stores[store][:lock_timeout]
        end

        # Finds a named store instance
        #
        # @param store [String] a store name
        # @raise [StandardError] for unknown stores
        def [](store)
          raise("Unknown data store %s" % store) unless include?(store)

          @stores[store][:store]
        end

        # List of known store names
        #
        # @return [Array<String>]
        def keys
          @stores.keys
        end

        # Determines if a store is known
        #
        # @return [Boolean]
        def include?(store)
          @stores.include?(store)
        end

        # Prepares all the stores
        def prepare
          @stores.each do |_, properties|
            properties[:store].from_hash(properties[:properties]).prepare
          end
        end

        # Creates a store instance for a given type
        #
        # @param name [String] the store instance name
        # @param type [String] store type
        # @return [DataStores::Base] data store instance
        # @raise [NameError] for unknown types
        def store_for(name, type)
          klass_name = "%sDataStore" % type.capitalize

          DataStores.const_get(klass_name).new(name, @playbook)
        rescue NameError
          raise("Cannot find a handler for Data Store type %s" % type)
        end

        # Initialize the data stores from playbook data
        #
        # @param data [Hash] playbook format data
        # @return [DataStores]
        def from_hash(data)
          @stores.clear

          data.each do |store, props|
            Log.debug("Loading data store %s" % [store])

            @stores[store] = {
              :properties => props,
              :type => props["type"],
              :lock_timeout => Integer(props.fetch("timeout", 120)),
              :store => store_for(store, props["type"])
            }
          end

          self
        end
      end
    end
  end
end

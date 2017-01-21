require_relative "base"
require "thread"

module MCollective
  module Util
    class Playbook
      class DataStores
        class MemoryDataStore < Base
          def startup_hook
            @store = {}
            @locks = {}
            @locks_mutex = Mutex.new
          end

          def read(key)
            raise("No such key %s" % [key]) unless include?(key)

            Marshal.load(Marshal.dump(@store[key]))
          end

          def write(key, value)
            @store[key] = value
          end

          def delete(key)
            @store.delete(key)
          end

          def lock(key)
            @locks_mutex.synchronize do
              @locks[key] ||= Mutex.new
            end

            @locks[key].lock
          end

          def release(key)
            @locks_mutex.synchronize do
              @locks[key] ||= Mutex.new
            end

            begin
              @locks[key].unlock
            rescue ThreadError
              Log.warn("Attempted to release lock %s but it was already unlocked" % key)
            end
          end

          def include?(key)
            @store.include?(key)
          end

          def prepare
            @store.clear
            @locks.clear
          end
        end
      end
    end
  end
end

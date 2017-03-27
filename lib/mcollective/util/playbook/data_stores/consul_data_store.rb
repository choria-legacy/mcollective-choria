module MCollective
  module Util
    class Playbook
      class DataStores
        class ConsulDataStore < Base
          def startup_hook
            require "diplomat"

            @session_mutex = Mutex.new
            @session_manager = nil
            @session_id = nil
          rescue LoadError
            raise("Consul Data Store is not functional. Please install the diplomat Gem.")
          end

          def lock(key, timeout)
            Timeout.timeout(timeout) do
              Diplomat::Lock.wait_to_acquire(key, session, nil, 2)
            end
          rescue Timeout::Error
            raise("Failed to obtain lock %s after %d seconds" % [key, timeout])
          end

          def release(key)
            Diplomat::Lock.release(key, session)
          end

          def read(key)
            Diplomat::Kv.get(key)
          end

          def write(key, value)
            Diplomat::Kv.put(key, value)
          end

          def delete(key)
            Diplomat::Kv.delete(key)
          end

          def ttl
            supplied = Integer(@properties.fetch("ttl", 10)).abs

            supplied < 10 ? 10 : supplied
          end

          def renew_session
            if @session_id
              Log.debug("Renewing Consul session %s" % [@session_id])
              Diplomat::Session.renew(@session_id)
            end
          end

          def start_session_manager
            @session_manager = Thread.new do
              begin
                loop do
                  renew_session

                  sleep(ttl - 5)
                end
              rescue
                Log.warn("Session manager for Consul data store %s failed: %s: %s" % [@name, $!.class, $!.to_s])

                sleep(1)

                retry
              end
            end
          end

          def session
            @session_mutex.synchronize do
              return @session_id if @session_id

              ttl_spec = "%ss" % ttl

              @session_id ||= Diplomat::Session.create("TTL" => ttl_spec, "Behavior" => "delete")

              start_session_manager

              @session_id
            end
          end
        end
      end
    end
  end
end

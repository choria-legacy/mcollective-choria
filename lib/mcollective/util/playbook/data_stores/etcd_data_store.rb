module MCollective
  module Util
    class Playbook
      class DataStores
        class EtcdDataStore < Base
          def startup_hook
            require "etcdv3"
          rescue LoadError
            raise("Etcd Data Store is not functional. Please install the etcdv3 Gem.")
          end

          def conn
            return @_conn if @_conn

            opts = {}
            opts[:url] = @properties.fetch("url", "http://127.0.0.1:2379")
            opts[:user] = @properties["user"] if @properties["user"]
            opts[:password] = @properties["password"] if @properties["password"]

            @_conn = Etcdv3.new(opts)
          end

          def read(key)
            result = conn.get(key)

            raise("Could not find key %s" % key) if !result || result.kvs.empty?

            result.kvs[0].value
          end

          def write(key, value)
            conn.put(key, value)
          end

          def delete(key)
            conn.del(key)
          end
        end
      end
    end
  end
end

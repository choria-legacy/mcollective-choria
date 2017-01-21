module MCollective
  module Util
    class Playbook
      class Tasks
        class DataTask < Base
          attr_reader :action, :key, :value, :options

          def run
            case @action
            when "write"
              written = @playbook.data_stores.write(@key, @value)
              [true, "Wrote value to %s" % [@key], [written]]

            when "delete"
              deleted = @playbook.data_stores.delete(@key)
              [true, "Deleted data item %s" % [@key], [deleted]]

            else
              [false, "Unknown action %s" % [@action], []]
            end
          rescue
            msg = "Could not perform %s on data %s: %s: %s" % [@action, @key, $!.class, $!.to_s]
            Log.debug(msg)
            Log.debug($!.backtrace.join("\t\n"))

            [false, msg, []]
          end

          def validate_configuration!
            raise("Action should be one of delete or write") unless ["delete", "write"].include?(@action)
            raise("A key to act on is needed") unless @key
            raise("A value is needed when writing") if @action == "write" && @value.nil?
          end

          def from_hash(properties)
            @action = properties["action"]
            @key = properties["key"]
            @value = properties["value"]
          end
        end
      end
    end
  end
end

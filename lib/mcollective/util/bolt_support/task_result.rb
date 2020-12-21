module MCollective
  module Util
    class BoltSupport
      class TaskResult
        attr_reader :host, :result

        # Method used by Puppet to create the TaskResult from a hash
        #
        # @param hash [Hash] hash as prodused by various execution_result method
        # @return [TaskResult]
        def self.from_asserted_hash(hash)
          new(hash.keys.first, hash.values.first)
        end

        # @param host [String] node name
        # @param result [Hash] result value as produced by execution_result methods
        def initialize(host, result)
          @host = host
          @result = result
        end

        def to_hash
          {@host => @result}
        end

        def to_json(obj={})
          to_hash.to_json(obj)
        end

        # A error object if this represents an error
        #
        # @return [Puppet::DataTypes::Error, nil]
        def error
          if @result["error"]
            if defined?(Puppet::DataTypes::Error)
              Puppet::DataTypes::Error.from_asserted_hash(@result["error"])
            else
              @result["error"]
            end
          end
        end

        # The type of task that created this result
        #
        # @return String examples like mcollective, data etc
        def type
          @result["type"]
        end

        # If this task result represents a succesful task
        #
        # This supposed fail_ok, any task with that set will be considered passed
        #
        # @return Boolean
        def ok
          return true if @result["fail_ok"]

          !@result.include?("error")
        end
        alias :ok? :ok

        def fail_ok
          @result["fail_ok"]
        end
        alias :fail_ok? :fail_ok

        # Access the value data embedded in the result
        #
        # @param key [String] data to access
        # @return [Object] the specifiv item in the value hash or the raw value
        def [](key)
          return @result["value"] unless @result["value"].is_a?(Hash)

          @result["value"][key]
        end

        # Access the value data in raw form
        #
        # @return [Object] whatever value the task produced
        def value
          @result["value"]
        end

        def to_s
          if Object.const_defined?(:Puppet)
            Puppet::Pops::Types::StringConverter.convert(self, "%p")
          else
            super
          end
        end
      end
    end
  end
end

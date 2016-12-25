module MCollective
  module Util
    class Playbook
      class Nodes
        class ShellNodes
          def initialize
            @script = nil
          end

          def prepare; end

          def validate_configuration!
            raise("No node source script specified") unless @script
            raise("Node source script is not executable") unless File.executable?(@script)
            raise("Node source script produced no results") if data.empty?
          end

          def from_hash(data)
            @script = data["script"]

            self
          end

          def valid_hostname?(host)
            host =~ /^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$/
          end

          def data
            return @_data if @_data

            @_data = `#{@script}`.lines.map do |line|
              line.chomp!

              raise("%s is not a valid certname" % line) unless valid_hostname?(line)

              line
            end
          end

          def discover
            data
          end
        end
      end
    end
  end
end

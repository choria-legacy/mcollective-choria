require "yaml"

module MCollective
  module Util
    class Playbook
      class Nodes
        class YamlNodes
          def initialize
            @group = nil
            @file = nil
          end

          def prepare; end

          def validate_configuration!
            raise("No node group YAML source file specified") unless @file
            raise("Node group YAML source file %s is not readable" % @file) unless File.readable?(@file)
            raise("No node group name specified") unless @group
            raise("No data group %s defined in the data file %s" % [@group, @file]) unless data.include?(@group)
            raise("Data group %s is not an array" % @group) unless data[@group].is_a?(Array)
            raise("Data group %s is empty" % @group) if data[@group].empty?
          end

          # Initialize the nodes source from a hash
          #
          # @param data [Hash] input with `group` and `source` keys
          # @return [PqlNodes]
          def from_hash(data)
            @group = data["group"]
            @file = data["source"]

            self
          end

          def data
            @_data ||= YAML.load(File.read(@file))
          end

          # Performs the PQL query and extracts certnames
          def discover
            data[@group]
          end
        end
      end
    end
  end
end

module MCollective
  module Util
    class Choria
      class Playbook
        class Inputs
          attr_reader :inputs

          def initialize(playbook)
            @inputs = {}
            @values = {}
          end

          def input_value(item)
            return @values[item] if @values.include?(item)
            return @inputs[item]["default"] if @inputs[item].include?("default")
            :unset
          end

          # @todo this is rubbish, mvp
          def values_from_hash(hash)
            @inputs.keys.each do |input|
              if @inputs[input].include?("default")
                default = @inputs[input]["default"]
              else
                default = :unset
              end

              found_value = hash.fetch(input, default)

              unless found_value == :unset
                @values[input] = found_value unless found_value == :unset
              end
            end
          end

          def from_source(inputs)
            @inputs = inputs
          end
        end
      end
    end
  end
end


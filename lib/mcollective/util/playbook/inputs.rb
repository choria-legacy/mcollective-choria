module MCollective
  module Util
    class Playbook
      class Inputs
        def initialize(playbook)
          @playbook = playbook
          @inputs = {}
        end

        # List of known input names
        #
        # @return [Array<String>]
        def keys
          @inputs.keys
        end

        # List of known input names that have static values
        #
        # @return [Array<String>]
        def static_keys
          keys - dynamic_keys
        end

        # List of known input names that have dynamic values
        #
        # @return [Array<String>]
        def dynamic_keys
          @inputs.select do |_, props|
            props[:dynamic]
          end.keys
        end

        # Creates options for each input in the application
        #
        # @param application [MCollective::Application]
        # @param set_required [Boolean] when true required inputs will be required on the CLI
        # @raise [StandardError] for invalidly defined inputs
        def add_cli_options(application, set_required)
          @inputs.each do |input, props|
            i_props = props[:properties]

            next if i_props["dynamic"]

            type = case i_props["type"]
                   when :string, "String"
                     String
                   when :fixnum, "Fixnum", "Integer"
                     Integer
                   when :float, "Float"
                     Float
                   when :numeric, "Numeric"
                     Numeric
                   when :array, ":array", "Array"
                     :array
                   when :bool, ":bool", ":boolean", "Boolean"
                     :boolean
                   else
                     raise("Invalid input type %s given for input %s" % [i_props["type"], input])
                   end

            description = "%s (%s) %s" % [i_props["description"], type, i_props["default"] ? ("default: %s" % i_props["default"]) : ""]

            option_params = {
              :description => description,
              :arguments => ["--%s %s" % [input.downcase, input.upcase]],
              :type => type
            }

            if set_required && !i_props.include?("data")
              option_params[:required] = i_props["required"]
            end

            application.class.option(input, option_params)
          end
        end

        # Attempts to find values for all declared inputs
        #
        # During tests saving to the ds can be skipped by setting
        # @save_during_prepare to false
        #
        # @param data [Hash] input data from CLI etc
        # @return [void]
        # @raise [StandardError] when required data could not be found
        # @raise [StandardError] when validation fails for any data
        def prepare(data={})
          @inputs.each do |input, props|
            next unless data.include?(input)
            next if data[input].nil?
            next if props[:properties]["dynamic"]

            validate_data(input, data[input])

            props[:value] = data[input]
            props[:dynamic] = false
          end

          validate_requirements
        end

        # Checks if a input is dynamic
        #
        # Dynaic inputs are those where the data is sourced from
        # a data source, an input that has a data source defined
        # and had a specific input given will not be dynamic
        #
        # @return [Boolean]
        def dynamic?(input)
          @inputs[input][:dynamic]
        end

        def include?(input)
          @inputs.include?(input)
        end

        # Looks up data from a datastore, returns default when not found
        #
        # @param input [String] input name
        # @return [Object] value from the ds
        # @raise [StandardError] for invalid inputs and ds errors
        def lookup_from_datastore(input)
          raise("Unknown input %s" % input) unless include?(input)

          properties = @inputs[input][:properties]

          value = @playbook.data_stores.read(properties["data"])
          validate_data(input, value)

          value
        rescue
          raise("Could not resolve %s for input %s: %s: %s" % [properties["data"], input, $!.class, $!.to_s]) unless properties.include?("default")

          Log.warn("Could not find %s, returning default value" % properties["data"])

          properties["default"]
        end

        # Saves static property values in their associated data stores for any keys with save set
        def save_input_data
          @inputs.each do |input, props|
            next unless props[:properties]["save"]
            next unless props[:properties]["data"]
            next unless props[:value]
            next if props[:dynamic]

            save_to_datastore(input)
          end
        end

        # Saves the value of a input to the data entry associated with it
        #
        # @see #save_input_data
        # @param input [String] input name
        # @raise [StandardError] for invalid inputs and ds errors
        def save_to_datastore(input)
          raise("Unknown input %s" % input) unless include?(input)

          i_data = @inputs[input]

          raise("Input %s has no value, cannot store it" % input) unless i_data.include?(:value)

          Log.debug("Saving value for input %s to data item %s" % [input, i_data[:properties]["data"]])

          @playbook.data_stores.write(i_data[:properties]["data"], i_data[:value])
        end

        # Retrieves the value for a specific input
        #
        # @param input [String] input name
        # @return [Object]
        # @raise [StandardError] for unknown inputs
        def [](input)
          raise("Unknown input %s" % input) unless include?(input)

          props = @inputs[input][:properties]

          if @inputs[input].include?(:value)
            Log.debug("Resolving %s as static" % [input])
            @inputs[input][:value]
          elsif props.include?("data")
            Log.debug("Resolving %s as dynamic" % [input])
            lookup_from_datastore(input)
          elsif props.include?("default")
            Log.debug("Resolving %s as default" % [input])
            props["default"]
          else
            raise("Input %s has no value, data source or default" % [input])
          end
        end

        # Retrieves the properties for a specific input
        #
        # @param input [String] input name
        # @return [Hash]
        # @raise [StandardError] for unknown inputs
        def input_properties(input)
          if include?(input)
            @inputs[input][:properties]
          else
            raise("Unknown input %s" % input)
          end
        end

        # Checks all required inputs have values
        #
        # @raise [StandardError] when not
        def validate_requirements
          invalid = @inputs.map do |input, props|
            next unless props[:properties]["required"]
            next if props[:properties].include?("data")

            unless props[:value]
              Log.warn("Input %s requires a value but has none or nil" % input)
              input
            end
          end.compact

          raise("Values were required but not given for inputs: %s" % invalid.join(", ")) unless invalid.empty?
        end

        # Validates a piece of data against an input
        #
        # @todo this seems quite limited, we have to expand with real needs
        # @param input [String] a valid input name
        # @param value [Object] a value to validate
        # @raise [StandardError] on validation failure
        def validate_data(input, value)
          return unless @inputs[input][:properties].include?("validation")

          validator = @inputs[input][:properties]["validation"]

          if validator =~ /^:(.+)/
            validator = $1.intern
          elsif validator =~ /^\/(.+)\/$/
            validator = Regexp.new($1)
          end

          Log.debug("Validating input %s using %s validator" % [input, validator])

          Validator.validate(value, validator)
        rescue
          Log.warn("Attempt to validate input %s with validator %s failed: %s" % [input, validator, $!.to_s]) if validator

          raise("Failed to validate value for input %s: %s" % [input, $!.to_s])
        end

        def from_hash(data)
          data.each do |input, props|
            props["required"] = true unless props.include?("required")

            Log.debug("Loading input %s" % [input])

            @inputs[input] = {
              :properties => props,
              :dynamic => props.include?("data")
            }
          end

          self
        end
      end
    end
  end
end

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
          @inputs.select do |_, props|
            !props[:dynamic]
          end.keys
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
        def add_cli_options(application, set_required)
          @inputs.each do |input, props|
            i_props = props[:properties]

            next if i_props["dynamic_only"]

            type = case i_props["type"]
                   when :string, "String"
                     String
                   when :fixnum, "Fixnum", "Integer"
                     Integer
                   else
                     i_props["type"]
                   end

            description = "%s (%s) %s" % [i_props["description"], type, i_props["default"] ? ("default: %s" % i_props["default"]) : ""]

            option_params = {
              :description => description,
              :arguments => ["--%s %s" % [input.downcase, input.upcase]],
              :type => type,
              :default => i_props["default"],
              :validation => i_props["validation"]
            }

            if set_required && !i_props.include?("data")
              option_params[:required] = i_props["required"]
            end

            application.class.option(input, option_params)
          end
        end

        # Attempts to find values for all declared inputs
        #
        # @param data [Hash] input data
        # @return [void]
        # @raise [StandardError] when required data could not be found
        # @raise [StandardError] when validation fails for any data
        def prepare(data={})
          @inputs.each do |input, _|
            next unless data.include?(input)
            next if data[input].nil?
            next if @inputs[input][:properties]["dynamic_only"]

            validate_data(input, data[input])
            @inputs[input][:value] = data[input]
            @inputs[input][:dynamic] = false
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

        # Retrieves the value for a specific input
        #
        # @param input [String] input name
        # @return [Object]
        # @raise [StandardError] for unknown inputs
        def [](input)
          raise("Unknown input %s" % input) unless include?(input)

          props = @inputs[input][:properties]

          if @inputs[input].include?(:value)
            @inputs[input][:value]
          elsif props.include?("data")
            lookup_from_datastore(input)
          elsif props.include?("default")
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

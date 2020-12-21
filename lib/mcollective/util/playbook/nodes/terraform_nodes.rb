module MCollective
  module Util
    class Playbook
      class Nodes
        class TerraformNodes
          def prepare; end

          def validate_configuration!
            raise("The supplied terraform path %s is not executable" % @terraform) if @terraform && !File.executable?(@terraform)
            raise("A terraform state file is needed") unless @state
            raise("The terraform statefile %s is not readable" % @state) unless File.readable?(@state)
            raise("An output name is needed") unless @output

            Validator.validate(@terraform, :shellsafe)
            Validator.validate(@state, :shellsafe)
            Validator.validate(@output, :shellsafe)
          end

          def from_hash(data)
            @state = data["statefile"]
            @output = data["output"]
            @terraform = data.fetch("terraform", choria.which("terraform"))

            self
          end

          def valid_hostname?(host)
            host =~ /^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$/
          end

          def tf_output
            shell = Shell.new("%s output -state %s -json %s 2>&1" % [@terraform, @state, @output])
            shell.runcommand

            raise("Terraform exited with code %d: %s" % [shell.status.exitstatus, shell.stdout]) unless shell.status.exitstatus == 0

            shell.stdout
          end

          def output_data
            return @_data if @_data

            data = JSON.parse(tf_output)

            raise("Only terraform outputs of type list is supported") unless data["type"] == "list"

            data["value"].each do |result|
              raise("%s is not a valid hostname" % result) unless valid_hostname?(result)
            end

            @_data = data["value"]
          end

          def choria
            @_choria ||= Util::Choria.new(false)
          end

          def discover
            output_data
          end
        end
      end
    end
  end
end

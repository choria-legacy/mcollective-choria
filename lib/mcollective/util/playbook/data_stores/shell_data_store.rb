require_relative "base"

module MCollective
  module Util
    class Playbook
      class DataStores
        class ShellDataStore < Base
          attr_reader :command, :timeout, :environment, :cwd

          def write(key, value)
            run("write", key, "CHORIA_DATA_VALUE" => value)

            nil
          end

          def delete(key)
            run("delete", key)

            nil
          end

          def read(key)
            run("read", key).stdout.chomp
          end

          def run(action, key, environment={})
            validate_key(key)

            command = "%s --%s" % [@command, action]
            options = shell_options

            options["environment"].merge!(
              environment.merge(
                "CHORIA_DATA_KEY" => key,
                "CHORIA_DATA_ACTION" => action
              )
            )

            shell = run_command(command, options)

            unless shell.status.exitstatus == 0
              Log.warn("While running command %s: %s" % [command, shell.stderr])
              raise("Could not %s key %s, got exitcode %d" % [action, key, shell.status.exitstatus])
            end

            shell
          end

          def run_command(command, options)
            shell = Shell.new(command, options)
            shell.runcommand
            shell
          end

          def validate_key(key)
            raise("Valid keys must match ^[a-zA-Z0-9_-]+$") unless key =~ /^[a-zA-Z0-9_-]+$/

            true
          end

          def from_hash(properties)
            @command = properties["command"]
            @timeout = properties.fetch("timeout", 10)
            @environment = properties.fetch("environment", {})
            @cwd = properties["cwd"]

            self
          end

          def validate_configuration!
            raise("A command is required") unless @command
            raise("Command %s is not executable" % @command) unless File.executable?(@command)
            raise("Timeout should be an integer") unless @timeout.to_i.to_s == @timeout.to_s

            if @environment
              raise("Environment should be a hash") unless @environment.is_a?(Hash)

              all_strings = @environment.map {|k, v| k.is_a?(String) && v.is_a?(String)}.all?
              raise("All keys and values in the environment must be strings") unless all_strings
            end

            if @cwd
              raise("cwd %s does not exist" % @cwd) unless File.exist?(@cwd)
              raise("cwd %s is not a directory" % @cwd) unless File.directory?(@cwd)
            end
          end

          def shell_options
            unless @__options
              @__options = {}
              @__options["cwd"] = @cwd if @cwd
              @__options["environment"] = @environment
              @__options["timeout"] = Integer(@timeout)
            end

            # bacause environment is being edited
            Marshal.load(Marshal.dump(@__options))
          end
        end
      end
    end
  end
end

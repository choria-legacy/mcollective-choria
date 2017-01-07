module MCollective
  module Util
    class Playbook
      class Tasks
        class ShellTask < Base
          def validate_configuration!
            raise("A command was not given") unless @command
            raise("Nodes were given but is not an array") if @nodes && !@nodes.is_a?(Array)
          end

          def from_hash(data)
            @cwd = data["cwd"] || Dir.pwd
            @timeout = data["timeout"]
            @nodes = data["nodes"]
            @environment = data["environment"]

            if @nodes.is_a?(Array)
              @command = "%s --nodes %s" % [data["command"], @nodes.join(",")]
            else
              @command = data["command"]
            end

            self
          end

          def shell_options
            options = {}
            options["cwd"] = @cwd if @cwd
            options["timeout"] = Integer(@timeout) if @timeout
            options["environment"] = @environment if @environment
            options["stdout"] = []
            options["stderr"] = options["stdout"]
            options
          end

          def run
            if @nodes
              Log.info("Starting command %s against %d nodes" % [@command, @nodes.size])
            else
              Log.info("Starting command %s" % [@command])
            end

            begin
              options = shell_options

              shell = Shell.new(@command, options)
              shell.runcommand

              options["stdout"].each do |output|
                output.lines.each do |line|
                  Log.info(line.chomp)
                end
              end

              if shell.status.exitstatus == 0
                Log.info("Successfully ran command %s" % [@command])
                [true, "Command completed successfully", options["stdout"]]
              else
                Log.warn("Failed to run command %s with exit code %s" % [@command, shell.status.exitstatus])
                [false, "Command failed with code %d" % [shell.status.exitstatus], options["stdout"]]
              end
            rescue
              msg = "Could not run command %s: %s: %s" % [@command, $!.class, $!.to_s]
              Log.debug(msg)
              Log.debug($!.backtrace.join("\t\n"))

              [false, msg, []]
            end
          end
        end
      end
    end
  end
end

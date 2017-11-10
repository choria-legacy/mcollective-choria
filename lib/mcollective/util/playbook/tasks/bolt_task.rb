module MCollective
  module Util
    class Playbook
      class Tasks
        class BoltTask < Base
          def validate_configuration!
            raise("Bolt requires one of task, plan or command") unless @task || @plan || @command
            raise("A path to Bolt modules is required") if !@command && !@modules
            raise("Bolt requires at least 1 node") if @nodes.empty?
            raise("Transports can only be winrm or ssh") unless ["winrm", "ssh"].include?(@transport)

            if @task || @plan
              @modules = File.expand_path(@modules)
              raise("The Bolt module path %s is not a directory" % @modules) unless File.directory?(@modules)
            end

            require_bolt
          end

          # Requires Bolt
          #
          # Done last since things are pretty hairy with this vendored puppet
          # I am sure there's issues with this, till Bolt ships built into puppet-agent
          # I doubt this will work particularly well.
          #
          # For sure I expect plan execution to not be possible
          def require_bolt
            # shuts up constant recreation warnings, can be removed when shipped in puppet-agent
            $VERBOSE = nil

            require "puppet"
            require "puppet/info_service"
            require "bolt"
            require "bolt/cli"
          end

          def from_hash(data)
            @task = data["task"]
            @plan = data["plan"]
            @command = data["command"]
            @user = data.fetch("user", ENV["USER"])
            @password = data["password"]
            @modules = data["modules"]
            @tty = data.fetch("tty", false)
            @parameters = data["parameters"]
            @nodes = data.fetch("nodes", [])
            @transport = data.fetch("transport", "ssh")
          end

          def nodes
            @nodes.map do |node|
              uri = node
              uri = "%s://%s" % [@transport, node] unless @transport == "ssh" || uri =~ /^(winrm|ssh):\/\/(.+)/

              Bolt::Node.from_uri(uri)
            end
          end

          def bolt_options
            options = {
              :nodes => nodes,
              :modules => @modules,
              :tty => @tty
            }

            options[:user] = @user if @user
            options[:password] = @password if @password

            options
          end

          def bolt_cli
            return @__cli if @__cli

            # We would rather pass a configured logger into bolt, see
            # https://github.com/puppetlabs/bolt/issues/79
            case @playbook.loglevel
            when "fatal"
              Bolt.log_level = ::Logger::FATAL
            when "error"
              Bolt.log_level = ::Logger::ERROR
            when "warn"
              Bolt.log_level = ::Logger::WARN
            when "debug"
              Bolt.log_level = ::Logger::DEBUG
            else
              Bolt.log_level = ::Logger::INFO
            end

            @__cli = Bolt::CLI.new({})
          end

          def bolt_executor
            @__executor ||= Bolt::Executor.new(nodes)
          end

          def run_command
            bolt_executor.run_command(@command)
          end

          def run_task
            path = @task
            input_method = nil

            unless File.exist?(path)
              path, metadata = bolt_cli.load_task_data(path, @modules)
              input_method = metadata["input_method"]
            end

            input_method ||= "both"

            bolt_executor.run_task(path, input_method, @parameters)
          end

          def log_results(results, elapsed)
            pass = []
            failed = []

            results.each_pair do |node, result|
              if result.success?
                Log.info("Success on node %s: %s" % [node.host, result.message.chomp])
                pass << result
              else
                Log.error("Failure on node %s: %s" % [node.host, result.message.chomp])
                failed << result
              end
            end

            if failed.empty?
              [true, "Successful Bolt run on %d nodes in %d seconds" % [@nodes.size, elapsed], results]
            else
              [false, "Failed Bolt run on %d / %d nodes in %d seconds" % [failed.size, @nodes.size, elapsed], results]
            end
          end

          def current_time
            Time.now
          end

          def to_execution_result(results)
            results[2]
          end

          def run
            results = []
            start = current_time

            begin
              if @task
                results = run_task
              elsif @command
                results = run_command
              elsif @plan
                raise("Executing Bolt plans is not currently supported")
              else
                raise("Did not receive a task, command or plan to execute")
              end

              log_results(results, Integer(Time.now - start))
            rescue
              msg = "Could not create Bolt action: %s: %s" % [$!.class, $!.to_s]
              Log.debug(msg)
              Log.debug($!.backtrace.join("\t\n"))

              [false, msg, {}]
            end
          end
        end
      end
    end
  end
end

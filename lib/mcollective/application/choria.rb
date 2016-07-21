module MCollective
  class Application
    class Choria < Application
      description "Orchastrator for Puppet Applications"

      usage <<-EOU
  mco choria [OPTIONS] [FILTERS] <ACTION>

  The ACTION can be one of the following:

     plan  - view the plan for a specific environment
     run   - run a the plan for a specific environment

  The environment is chosen using --environment and the concurrent
  runs may be limited using --batch.

  The batching works a bit different than typical, it will only batch
  based on a sorted list of certificate names, this means the batches
  will always run in predictable order.
  EOU

      exclude_argument_sections "common", "filter", "rpc"

      option :environment,
             :arguments => ["--environment ENVIRONMENT"],
             :description => "The environment to run, defaults to production",
             :type => String

      option :batch,
             :arguments => ["--batch SIZE"],
             :description => "Run the nodes in each group in batches of a certain size",
             :type => Integer

      def post_option_parser(configuration)
        if ARGV.length >= 1
          configuration[:command] = ARGV.shift
        else
          abort("Please specify a command, valid commands are: %s" % valid_commands.join(", "))
        end

        unless valid_commands.include?(configuration[:command])
          abort("Unknown command %s, valid commands are: %s" % [configuration[:command], valid_commands.join(", ")])
        end
      end

      def main
        Util.loadclass("MCollective::Util::Choria")
        send("%s_command" % configuration[:command])
      end

      # Shows the execution plan
      #
      # @return [void]
      def plan_command
        show_plan(choria.puppet_environment)
      end

      # Shows and run the plan
      #
      # @return [void]
      def run_command
        env = choria.puppet_environment

        show_plan(env)

        confirm("Are you sure you wish to run this plan?")

        puts

        run_plan(env)
      end

      # Creates and cache a client to the Puppet RPC Agent
      #
      # @return [RPC::Client]
      def puppet
        return @client if @client

        @client = rpcclient("puppet")

        @client.limit_targets = false
        @client.progress = false
        @client.batch_size = 0

        @client
      end

      # Creates and cache a Choria helper class
      #
      # @return [Util::Choria]
      def choria
        @_choria ||= Util::Choria.new(configuration[:environment])
      end

      # Shows the plan for a specific environment
      #
      # @param env [Util::Choria::PuppetV3Environment]
      # @return [void]
      def show_plan(env)
        puts("Puppet Site Plan for the %s Environment" % bold(env.environment))
        puts
        puts("%s applications on %s managed nodes:" % [bold(env.applications.size), bold(env.nodes.size)])
        puts
        env.applications.each do |app|
          puts("\t%s" % app)
        end
        puts
        puts("Node groups and run order:")

        cnt = 1

        env.each_node_group do |group|
          puts("   %s %s %s" % [green("   ---"), bold("Group %d" % cnt), green("--------------------------------------")])
          puts

          group.each do |node|
            puts("\t%s" % bold(node))

            app_resources = env.node(node)[:application_resources].sort_by {|k, _| k}

            app_resources.each do |app, resources|
              puts("\t\t%s -> %s" % [app, resources.sort.join(", ")])
            end
            puts
          end

          cnt += 1
        end
      end

      # Enables and Runs Puppet on a list of nodes
      #
      # @param nodes [Array<String>] node names to run
      def run_nodes(nodes)
        log("Running Puppet on %s nodes" % bold(nodes.size))

        puppet.discover(:nodes => nodes)

        enable_nodes(nodes)
        puppet.runonce(:splay => false, :use_cached_catalog => false, :force => true)
        wait_till_nodes_start(nodes)
        wait_till_nodes_idle(nodes)
        disable_nodes(nodes)
      end

      # Determines if all the given nodes have Puppet enabled
      #
      # @param nodes [Array<String>] nodes to check
      # @return [Boolean]
      def all_nodes_enabled?(nodes)
        log("Checking if %s nodes are enabled" % bold(nodes.size))

        puppet.discover(:nodes => nodes)
        puppet.status.map {|resp| resp.results[:data][:enabled]}.all?
      end

      # Disables Puppet on the given nodes with a message
      #
      # @param nodes [Array<String>] nodes to disable
      # @return [void]
      def disable_nodes(nodes)
        msg = "Disabled during orchastration job initiated by %s at %s" % [choria.certname, Time.now]
        log("Disabling Puppet on %s nodes" % [bold(nodes.size)])

        puppet.discover(:nodes => nodes)
        puppet.disable(:message => msg)
      end

      # Enables Puppet on the given nodes
      #
      # @param nodes [Array<String>] list of nodes to enable
      # @return [void]
      def enable_nodes(nodes)
        log("Enabling Puppet on %s nodes" % [bold(nodes.size)])
        puppet.discover(:nodes => nodes)
        puppet.enable
      end

      # Waits for Puppet to start running on a list of nodes
      #
      # After starting puppet using `runonce` there is a delay while Ruby
      # starts up and becomes `ready`.  This waits for it to become ready
      # by checking a number of times for the `:applying` status.
      #
      # @note when the nodes never start a message is printed and the program exits
      # @param nodes [Array<String>] list of nodes to check
      # @param count [Integer] how many times to try them
      # @param sleep_time [Numeric] how long to wait between checks
      # @return [void]
      def wait_till_nodes_start(nodes, count=40, sleep_time=5)
        puppet.discover(:nodes => nodes)

        count.times do |i|
          log("Waiting for %s nodes to start a run" % bold(nodes.size)) if i % 4 == 0

          return if puppet.status.map {|resp| resp.results[:data][:applying] }.all?
          sleep sleep_time
        end

        puts(red("Failed to start %s nodes after %d tries" % [nodes.size, count]))
        nodes.each do |node|
          puts("\t%s" % bold(node))
        end

        exit(1)
      end

      # Waits for nodes that are applying to become idle
      #
      # After applying starts it will eventually progress to a idle state, this
      # waits for all the given nodes to become idle
      #
      # @note when the nodes never start a message is printed and the program exits
      # @param nodes [Array<String>] list of nodes to check
      # @param count [Integer] how many times to try them
      # @param sleep_time [Numeric] how long to wait between checks
      # @return [void]
      def wait_till_nodes_idle(nodes, count=40, sleep_time=5)
        puppet.discover(:nodes => nodes)

        count.times do |i|
          log("Waiting for %s nodes to become idle" % bold(nodes.size)) if i % 4 == 0

          return if puppet.status.map {|resp| resp.results[:data][:applying] }.none?
          sleep sleep_time
        end

        puts(red("Waited a %d seconds for %s nodes to become idle, cannot continue" % [(count * sleep_time), nodes.size]))

        nodes.each do |node|
          puts("\t%s" % bold(node))
        end

        exit(1)
      end

      # Checks on the given nodes if any had failed resources and returns the failed list
      #
      # @param nodes [Array<String>] the nodes to check
      # @return [Array<String>] nodes that had resource failures
      def failed_nodes(nodes)
        puppet.discover(:nodes => nodes)

        puppet.last_run_summary.select {|resp| resp.results[:data][:failed_resources] > 0}.map {|r| r.results[:sender]}
      end

      # Runs the environment plan
      #
      # The basic flow is:
      #
      #   - fail if all the nodes in the plan are not enabled
      #   - disable all nodes so that manual and scheduled runs are not happening
      #   - wait for all nodes to idle
      #   - for every group
      #     - enable and run them
      #     - wait for them to become idle
      #     - disable them
      #     - fail if any nodes had failed resources
      #   - enable all nodes back to normal operation
      #
      # @note on failure this will exit the program
      # @param env [Util::Choria::PuppetV3Environment]
      # @return [void]
      def run_plan(env)
        batch_size = configuration.fetch(:batch, env.nodes.size)
        gc = 1

        unless all_nodes_enabled?(env.nodes)
          abort(red("Not all nodes in the plan are enabled, cannot continue"))
        end

        disable_nodes(env.nodes)
        wait_till_nodes_idle(env.nodes)

        env.each_node_group do |group|
          start_time = Time.now

          puts

          if batch_size
            puts("Running node %s with %s nodes batched %s a time" % [bold("Group %s" % gc), bold(group.size), bold(batch_size)])
          else
            puts("Running node %s with %s nodes" % [bold("Group %s" % gc), bold(group.size)])
          end

          group.in_groups_of(batch_size) do |group_nodes|
            run_nodes(group_nodes.compact)
          end

          if !(failed = failed_nodes(group)).empty?
            puts("Puppet failed to run on %s / %s nodes, cannot continue" % [red(failed.size), red(group.size)])

            failed.each do |node|
              puts("\t%s" % bold(node))
            end

            exit(1)
          else
            elapsed = "%0.2f" % [Time.now - start_time]
            puts
            puts("Succesful run of %s nodes in %s in %s seconds" % [green(group.size), bold("Group %s" % gc), bold(elapsed)])
          end

          gc += 1
        end
      ensure
        puts
        enable_nodes(env.nodes)
      end

      # List of valid commands this application respond to
      #
      # @return [Array<String>] like `plan` and `run`
      def valid_commands
        methods.grep(/_command$/).map {|c| c.to_s.gsub("_command", "")}
      end

      # Validates the configuration
      #
      # @return [void]
      def validate_configuration(configuration)
        configuration[:environment] ||= "production"
      end

      # Asks the user to confirm something on the CLI
      #
      # @note exits the application on no
      # @param msg [String] the message to ask
      # @return [void]
      def confirm(msg)
        print("%s (y/n) " % msg)

        STDOUT.flush

        exit(1) unless STDIN.gets.strip =~ /^(?:y|yes)$/i
      end

      # Logs a message to STDOUT
      #
      # @param msg [String] what to log
      def log(msg)
        puts("        %s: %s" % [Time.now, msg])
      end

      def green(msg)
        Util.colorize(:green, msg)
      end

      def bold(msg)
        Util.colorize(:bold, msg)
      end

      def red(msg)
        Util.colorize(:red, msg)
      end
    end
  end
end

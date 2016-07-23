module MCollective
  module Util
    class Choria
      # Class to orchastrate the various nodes in a puppet environment catalog
      #
      # @note currently assumes its run on the CLI and will puts various stuff to STDOUT
      class Orchestrator
        attr_reader :puppet, :choria, :environment, :certname
        attr_accessor :batch_size

        def initialize(choria, puppet, batch_size)
          @puppet = puppet
          @choria = choria
          @environment = choria.puppet_environment
          @certname = choria.certname
          @batch_size = batch_size
        end

        def time_stamp
          Time.now
        end

        # Disables Puppet on the given nodes with a message
        #
        # @param nodes [Array<String>] nodes to disable
        # @return [void]
        def disable_nodes(nodes)
          log("Disabling Puppet on %s nodes" % [bold(nodes.size)])

          msg = "Disabled during orchastration job initiated by %s at %s" % [certname, time_stamp]

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
        # @param nodes [Array<String>] list of nodes to check
        # @param count [Integer] how many times to try them
        # @param sleep_time [Numeric] how long to wait between checks
        # @return [Boolean]
        # @raise [Abort] on failure
        def wait_till_nodes_start(nodes, count=40, sleep_time=5)
          count.times do |i|
            log("Waiting for %s nodes to start a run" % bold(nodes.size)) if i % 4 == 0

            puppet.discover(:nodes => nodes)

            return true if puppet.status.map {|resp| resp.results[:data][:applying] }.all?
            sleep sleep_time
          end

          puts(red("Failed to start %s nodes after %d tries:" % [nodes.size, count]))
          nodes.each do |node|
            puts("\t%s" % bold(node))
          end

          raise(Abort)
        end

        # Waits for nodes that are applying to become idle
        #
        # After applying starts it will eventually progress to a idle state, this
        # waits for all the given nodes to become idle
        #
        # @param nodes [Array<String>] list of nodes to check
        # @param count [Integer] how many times to try them
        # @param sleep_time [Numeric] how long to wait between checks
        # @return [void]
        # @raise [Abort] on failure
        def wait_till_nodes_idle(nodes, count=40, sleep_time=5)
          count.times do |i|
            log("Waiting for %s nodes to become idle" % bold(nodes.size)) if i % 4 == 0

            puppet.discover(:nodes => nodes)

            return if puppet.status.map {|resp| resp.results[:data][:applying] }.none?

            sleep sleep_time
          end

          puts(red("Waited a %d seconds for %s nodes to become idle, cannot continue" % [(count * sleep_time), nodes.size]))

          nodes.each do |node|
            puts("\t%s" % bold(node))
          end

          raise(Abort)
        end

        # Checks on the given nodes if any had failed resources and returns the failed list
        #
        # @param nodes [Array<String>] the nodes to check
        # @return [Array<String>] nodes that had resource failures
        def failed_nodes(nodes)
          puppet.discover(:nodes => nodes)

          puppet.last_run_summary.select {|resp| resp.results[:data][:failed_resources] > 0}.map {|r| r.results[:sender]}.compact
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
        # @return [void]
        # @raise [UserError] when node status prevents plan from being run
        # @raise [Abort, StandardError] on other failure
        def run_plan
          batch = batch_size || environment.nodes.size
          gc = 1

          unless all_nodes_enabled?(environment.nodes)
            raise(UserError, "Not all nodes in the plan are enabled, cannot continue")
          end

          disable_nodes(environment.nodes)

          wait_till_nodes_idle(environment.nodes)

          environment.each_node_group do |group|
            start_time = time_stamp

            puts

            if batch
              puts("Running node %s with %s nodes batched %s a time" % [bold("Group %s" % gc), bold(group.size), bold(batch)])
            else
              puts("Running node %s with %s nodes" % [bold("Group %s" % gc), bold(group.size)])
            end

            group.in_groups_of(batch) do |group_nodes|
              group_nodes.compact!

              run_nodes(group_nodes)

              unless (failed = failed_nodes(group_nodes)).empty?
                puts("Puppet failed to run on %s / %s nodes, cannot continue" % [red(failed.size), red(group_nodes.size)])

                failed.each do |node|
                  puts("\t%s" % bold(node))
                end

                raise(Abort)
              end
            end

            elapsed = "%0.2f" % [time_stamp - start_time]
            puts
            puts("Succesful run of %s nodes in %s in %s seconds" % [green(group.size), bold("Group %s" % gc), bold(elapsed)])

            gc += 1
          end
        ensure
          puts
          enable_nodes(environment.nodes) unless $!.is_a?(UserError)
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

        # Enables and Runs Puppet on a list of nodes
        #
        # @param nodes [Array<String>] node names to run
        def run_nodes(nodes)
          log("Running Puppet on %s nodes" % bold(nodes.size))

          enable_nodes(nodes)

          puppet.discover(:nodes => nodes)
          puppet.runonce(:splay => false, :use_cached_catalog => false, :force => true)

          wait_till_nodes_start(nodes)
          wait_till_nodes_idle(nodes)
          disable_nodes(nodes)
        end

        def to_s
          plan = StringIO.new

          plan.puts("Puppet Site Plan for the %s Environment" % bold(environment.environment))
          plan.puts
          plan.puts("%s applications on %s managed nodes:" % [bold(environment.applications.size), bold(environment.nodes.size)])
          plan.puts

          environment.applications.each do |app|
            plan.puts("\t%s" % app)
          end

          plan.puts
          plan.puts("Node groups and run order:")

          cnt = 1

          environment.each_node_group do |group|
            plan.puts("   %s %s %s" % [green("   ---"), bold("Group %d" % cnt), green("--------------------------------------")])
            plan.puts

            group.each do |node|
              plan.puts("\t%s" % bold(node))

              app_resources = environment.node(node)[:application_resources].sort_by {|k, _| k}

              app_resources.each do |app, resources|
                plan.puts("\t\t%s -> %s" % [app, resources.sort.join(", ")])
              end
              plan.puts
            end

            cnt += 1
          end

          plan.string
        end

        # Logs a message to STDOUT
        #
        # @param msg [String] what to log
        def log(msg)
          puts("        %s: %s" % [time_stamp, msg])
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
end

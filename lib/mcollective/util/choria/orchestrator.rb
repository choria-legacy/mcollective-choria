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

        def empty?
          environment.applications.empty?
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

          rpc_and_check(:disable, nodes, :message => msg)
        end

        # Enables Puppet on the given nodes
        #
        # @param nodes [Array<String>] list of nodes to enable
        # @return [void]
        def enable_nodes(nodes)
          log("Enabling Puppet on %s nodes" % [bold(nodes.size)])

          rpc_and_check(:enable, nodes)
        end

        # Checks the result set from a mcollective request and log/raise on error
        #
        # @param result [Hash] the extended block based result from mcollective
        # @param raise_on_fail [Boolean] raise a UserError on any failures
        # @raise [UserError] on detected failure in results when raise_on_fail is true
        # @return [Boolean]
        def check_result(result, raise_on_fail=true)
          return true if result[:body][:statuscode] == 0

          msg = "Failed response from node %s agent %s: %s" % [result[:senderid], result[:senderagent], result[:body][:statusmsg]]

          if raise_on_fail
            raise(UserError, msg)
          else
            log(msg)

            false
          end
        end

        # Performs an RPC action check results and return them
        #
        # This will run a action on a set of nodes with specific arguments
        # the results will be checked and any nodes that failed - like when
        # maybe actionpolicy prevents something - this will raise a UserError
        # otherwise the SimpleRPC style results are returned as a array
        #
        # @param action [Symbol] action to execute
        # @param nodes [Array<String>] node identities
        # @param args [Hash] arguments for the RPC request
        # @return [Array<Hash>] SimpleRPC results
        # @raise [UserError] when results fail
        def rpc_and_check(action, nodes, args={})
          results = []

          puppet.discover(:nodes => nodes)
          puppet.send(action, args) do |result, s_result|
            check_result(result, true)
            results << s_result
          end

          results
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
        # @raise [UserError] on failure
        def wait_till_nodes_start(nodes, count=40, sleep_time=5)
          count.times do |i|
            log("Waiting for %s nodes to start a run" % bold(nodes.size)) if i % 4 == 0

            return true if rpc_and_check(:status, nodes).map {|resp| resp.results[:data][:applying] }.all?
            sleep sleep_time
          end

          puts(red("Failed to start %s nodes after %d tries:" % [nodes.size, count]))
          nodes.each do |node|
            puts("\t%s" % bold(node))
          end

          raise(UserError, "Timeout while waiting for nodes to start. This might be due to stuck daemons or very long running Puppet runs")
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
        # @raise [UserError] on failure
        def wait_till_nodes_idle(nodes, count=40, sleep_time=5)
          count.times do |i|
            log("Waiting for %s nodes to become idle" % bold(nodes.size)) if i % 4 == 0

            return if rpc_and_check(:status, nodes).map {|resp| resp.results[:data][:applying] }.none?

            sleep sleep_time
          end

          puts(red("Waited a %d seconds for %s nodes to become idle, cannot continue" % [(count * sleep_time), nodes.size]))

          nodes.each do |node|
            puts("\t%s" % bold(node))
          end

          raise(UserError, "Timeout while waiting for nodes to idle in order to start the next step. This might be due to stuck daemons or very long running Puppet runs")
        end

        # Checks on the given nodes if any had failed resources and returns the failed list
        #
        # @param nodes [Array<String>] the nodes to check
        # @return [Array<String>] nodes that had resource failures
        def failed_nodes(nodes)
          rpc_and_check(:last_run_summary, nodes).select {|resp| resp.results[:data][:failed_resources] > 0}.map {|r| r.results[:sender]}.compact
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
        # @raise [UserError, StandardError] on other failure
        def run_plan
          gc = 1

          unless all_nodes_enabled?(environment.nodes)
            raise(UserError, "Not all nodes in the plan are enabled, cannot continue")
          end

          disable_nodes(environment.nodes)

          wait_till_nodes_idle(environment.nodes)

          environment.each_node_group do |group|
            start_time = time_stamp

            puts

            batch = batch_size || group.size

            if batch
              puts("Running node %s with %s nodes batched %s a time" % [bold("Group %s" % gc), bold(group.size), bold(batch)])
            else
              puts("Running node %s with %s nodes" % [bold("Group %s" % gc), bold(group.size)])
            end

            group.in_groups_of(batch) do |group_nodes|
              group_nodes.compact!

              run_nodes(group_nodes)

              unless (failed = failed_nodes(group_nodes)).empty?
                puts("Puppet failed to run without any failed resources on %s / %s nodes, cannot continue" % [red(failed.size), red(group_nodes.size)])

                failed.each do |node|
                  puts("\t%s" % bold(node))
                end

                raise(UserError, "Puppet failed to run without any failed resources on %s / %s nodes, cannot continue" % [failed.size, group_nodes.size])
              end
            end

            elapsed = "%0.2f" % [time_stamp - start_time]
            puts
            puts("Succesful run of %s nodes in %s in %s seconds" % [green(group.size), bold("Group %s" % gc), bold(elapsed)])

            gc += 1
          end
        rescue UserError => original
          log(red("Encountered an error that might result in nodes being in an unknown state, attempting to disable Puppet for user investigation"))

          begin
            disable_nodes(environment.nodes)
          rescue
            log(red("While attempting to disable Puppet additional failures were encountered: %s" % $!.to_s))
          end

          raise(original)
        ensure
          puts

          enable_nodes(environment.nodes) unless $!
        end

        # Determines if all the given nodes have Puppet enabled
        #
        # @param nodes [Array<String>] nodes to check
        # @return [Boolean]
        def all_nodes_enabled?(nodes)
          log("Checking if %s nodes are enabled" % bold(nodes.size))

          rpc_and_check(:status, nodes).map {|resp| resp.results[:data][:enabled]}.all?
        end

        # Enables and Runs Puppet on a list of nodes
        #
        # @param nodes [Array<String>] node names to run
        def run_nodes(nodes)
          log("Running Puppet on %s nodes" % bold(nodes.size))

          enable_nodes(nodes)

          rpc_and_check(:runonce, nodes, :splay => false, :use_cached_catalog => false, :force => true)

          wait_till_nodes_start(nodes)
          wait_till_nodes_idle(nodes)
          disable_nodes(nodes)
        end

        def to_s
          plan = StringIO.new

          plan.puts("Puppet Site Plan for the %s Environment" % bold(environment.environment))
          plan.puts

          if empty?
            plan.puts("No site applications were found in the Puppet environment")
            return(plan.string)
          end

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

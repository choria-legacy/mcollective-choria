module MCollective
  class Application
    class Choria < Application
      description "Orchastrator for Puppet Applications"

      usage <<-EOU
  mco choria [OPTIONS] <ACTION>

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

      option :instance,
             :arguments => ["--instance INSTANCE"],
             :description => "Limit to a specific application instance",
             :type => String

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

      # Validates the configuration
      #
      # @return [void]
      def validate_configuration(configuration)
        configuration[:environment] ||= "production"
      end

      def main
        Util.loadclass("MCollective::Util::Choria")
        send("%s_command" % configuration[:command])

      rescue Util::Choria::UserError
        STDERR.puts("Could not process site plan: %s" % orchestrator.red($!.to_s))

      rescue Util::Choria::Abort
        exit(1)
      end

      # Shows the execution plan
      #
      # @return [void]
      def plan_command
        puts orchestrator.to_s
      end

      # Shows and run the plan
      #
      # @return [void]
      def run_command
        puts orchestrator.to_s

        confirm("Are you sure you wish to run this plan?")

        puts

        orchestrator.run_plan
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
        @_choria ||= Util::Choria.new(configuration[:environment], configuration[:instance])
      end

      # Creates and cache a Choria Orchastrator
      #
      # @return [Util::Choria::Orchestrator]
      def orchestrator
        @_orchestrator ||= choria.orchestrator(puppet, configuration[:batch])
      end

      # List of valid commands this application respond to
      #
      # @return [Array<String>] like `plan` and `run`
      def valid_commands
        methods.grep(/_command$/).map {|c| c.to_s.gsub("_command", "")}
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
    end
  end
end

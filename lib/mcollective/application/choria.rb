module MCollective
  class Application
    class Choria < Application
      description "Orchestrator for Puppet Applications"

      usage <<-EOU
  mco choria [OPTIONS] <ACTION>

  The ACTION can be one of the following:

     plan         - view the plan for a specific environment
     run          - run a the plan for a specific environment
     request_cert - requests a certificate from the Puppet CA

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

      option :ca,
             :arguments => ["--ca SERVER"],
             :description => "Address of your Puppet CA",
             :type => String

      option :certname,
             :arguments => ["--certname CERTNAME"],
             :description => "Override the default certificate name",
             :type => String

      def post_option_parser(configuration)
        if ARGV.length >= 1
          configuration[:command] = ARGV.shift
        else
          abort("Please specify a command, valid commands are: %s" % valid_commands.join(", "))
        end

        configuration[:environment] ||= "production"

        ENV["MCOLLECTIVE_CERTNAME"] = configuration[:certname] if configuration[:certname]
      end

      # Validates the configuration
      #
      # @return [void]
      def validate_configuration(configuration)
        Util.loadclass("MCollective::Util::Choria")

        unless valid_commands.include?(configuration[:command])
          abort("Unknown command %s, valid commands are: %s" % [configuration[:command], valid_commands.join(", ")])
        end

        if !choria.has_client_public_cert? && configuration[:command] != "request_cert"
          abort("A certificate is needed from the Puppet CA for `%s`, please use the `request_cert` command" % choria.certname)
        end
      end

      def main
        send("%s_command" % configuration[:command])

      rescue Util::Choria::UserError
        STDERR.puts("Could not process site plan: %s" % orchestrator.red($!.to_s))

      rescue Util::Choria::Abort
        exit(1)
      end

      # Requests a certificate from the CA
      #
      # @return [void]
      def request_cert_command
        disconnect

        if choria.has_client_public_cert?
          raise(Util::Choria::UserError, "Already have a certificate '%s', cannot request a new one" % choria.client_public_cert)
        end

        choria.ca = configuration[:ca] if configuration[:ca]

        certname = choria.client_public_cert

        choria.make_ssl_dirs
        choria.fetch_ca

        if choria.waiting_for_cert?
          puts("Certificate %s has already been requested, attempting to retrieve it" % certname)
        else
          puts("Requesting certificate for '%s'" % certname)
          choria.request_cert
        end

        puts("Waiting up to 240 seconds for it to be signed")
        puts

        24.times do |time|
          print "Attempting to download certificate %s: %d / 24\r" % [certname, time]

          break if choria.attempt_fetch_cert

          sleep 10
        end

        unless choria.has_client_public_cert?
          raise(Util::Choria::UserError, "Could not fetch the certificate after 240 seconds, please ensure it gets signed and rerun this command")
        end

        puts("Certificate %s has been stored in %s" % [certname, choria.ssl_dir])
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
        @_choria ||= Util::Choria.new(configuration[:environment], configuration[:instance], false)
      end

      # Creates and cache a Choria Orchastrator
      #
      # @return [Util::Choria::Orchestrator]
      def orchestrator
        @_orchestrator ||= begin
                             choria.check_ssl_setup
                             choria.orchestrator(puppet, configuration[:batch])
                           end
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

module MCollective
  class Application
    class Federation < Application
      description "Choria Federation Brokers"

      usage <<-EOU
mco federation [OPTIONS] <ACTION>

The ACTION can be one of the following:

   observe       - view the published Federation Broker statistics
   broker        - start a Federation Broker instance

EOU

      exclude_argument_sections "common", "filter", "rpc"

      option :cluster,
             :arguments => ["--cluster CLUSTER"],
             :description => "Cluster name to observe or serve",
             :type => String

      option :instance,
             :arguments => ["--instance INSTANCE"],
             :description => "Instance name to observe or serve",
             :type => String

      option :stats_port,
             :arguments => ["--stats-port PORT", "--stats"],
             :description => "HTTP port to listen to for stats",
             :type => Integer

      def broker_command
        configuration[:cluster] = Config.instance.pluginconf["choria.federation.cluster"] unless configuration[:cluster]
        configuration[:instance] = Config.instance.pluginconfig["choria.federation.instance"] unless configuration[:instance]

        abort("A cluster name is required, use --cluster or plugin.choria.federation.cluster") unless configuration[:cluster]

        Log.warn("Using a UUID based instance name, use --instance of plugin.choria.federation.instance") unless configuration[:instance]

        broker = choria.federation_broker(
          configuration[:cluster],
          configuration[:instance],
          configuration[:stats_port]
        )

        broker.start

        sleep 10 while broker.ok?

        Log.error("Some broker threads died, exiting: %s" % broker.thread_status.pretty_inspect)

        exit(1)
      end

      def observe_command
        abort("Cannot observe using a client that is not configured for Federation, please set choria.federation.collectives or CHORIA_FED_COLLECTIVE") unless choria.federated?

        puts "Waiting for cluster stats to be published ...."

        choria.federation_broker(configuration[:cluster]).observe_stats do |stats|
          next if stats.empty?

          print "\e[H\e[2J"

          puts "Federation Broker: %s" % Util.colorize(:bold, configuration[:cluster])
          puts

          ["federation", "collective"].each do |type|
            type_stats = {"sent" => 0, "received" => 0, "instances" => {}}

            stats.keys.sort.each do |instance|
              type_stats["sent"] += stats[instance][type]["sent"]
              type_stats["received"] += stats[instance][type]["received"]
              type_stats["instances"][instance] ||= {}
              type_stats["instances"][instance][type] = {
                "sent" => stats[instance][type]["sent"],
                "received" => stats[instance][type]["received"],
                "last" => stats[instance][type]["lasst_message"]
              }
            end

            puts "%s" % Util.colorize(:bold, type.capitalize)
            puts "  Totals:"
            puts "    Received: %d  Sent: %d" % [type_stats["received"], type_stats["sent"]]
            puts
            puts "  Instances:"

            padding = type_stats["instances"].keys.map(&:length).max + 4

            type_stats["instances"].keys.sort.each do |instance|
              puts "%#{padding}s: Received: %d (%.1f%%) Sent: %d (%.1f%%)" % [
                instance,
                type_stats["instances"][instance][type]["received"],
                type_stats["instances"][instance][type]["received"] / type_stats["received"].to_f * 100,
                type_stats["instances"][instance][type]["sent"],
                type_stats["instances"][instance][type]["sent"] / type_stats["sent"].to_f * 100
              ]
            end

            puts
          end

          puts Util.colorize(:bold, "Instances:")

          stats.keys.sort.each do |instance|
            puts "  %s version %s started %s" % [
              instance,
              stats[instance]["version"],
              Time.at(stats[instance]["start_time"]).strftime("%F %T")
            ]
          end

          puts
          puts "Updated: %s" % Time.now.strftime("%F %T")
        end
      end

      # Creates and cache a Choria helper class
      #
      # @return [Util::Choria]
      def choria
        @_choria ||= Util::Choria.new
      end

      def post_option_parser(configuration)
        if ARGV.length >= 1
          configuration[:command] = ARGV.shift
        else
          abort("Please specify a command, valid commands are: %s" % valid_commands.join(", "))
        end
      end

      def validate_configuration(configuration)
        Util.loadclass("MCollective::Util::Choria")

        unless valid_commands.include?(configuration[:command])
          abort("Unknown command %s, valid commands are: %s" % [configuration[:command], valid_commands.join(", ")])
        end

        if !choria.has_client_public_cert? && !["request_cert", "show_config"].include?(configuration[:command])
          abort("A certificate is needed from the Puppet CA for `%s`, please use the `request_cert` command" % choria.certname)
        end

        if configuration[:command] == "observe"
          abort("When observing a Federation Broker the --cluster option is required") unless configuration[:cluster]
        end
      end

      def main
        send("%s_command" % configuration[:command])
      rescue Interrupt
        exit
      end

      # List of valid commands this application respond to
      #
      # @return [Array<String>] like `plan` and `run`
      def valid_commands
        methods.grep(/_command$/).map {|c| c.to_s.gsub("_command", "")}
      end
    end
  end
end

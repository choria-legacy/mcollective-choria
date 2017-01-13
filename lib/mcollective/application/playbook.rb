module MCollective
  class Application
    class Playbook < Application
      description "Choria Playbook Runner"

      usage <<-EOU
  mco playbook [OPTIONS] <ACTION> <PLAYBOOK>

  The ACTION can be one of the following:

    show      - preview the playbook in parsed YAML format
    run       - run the playbook as your local user

  The PLAYBOOK is a YAML file describing the tasks

  Passing --help as well as a PLAYBOOK argument will show
  flags and help related to the specific playbook.

  Any inputs to the playbook should be given on the CLI.

  A report can be produced using the --report argument
  when running a playbook
  EOU

      exclude_argument_sections "common", "filter", "rpc"

      # Parse out all options and look for any yaml|yml files in the remaining arguments
      #
      # @return [String,nil]
      def pre_parse_find_yaml
        return ARGV.last if ARGV.last && ARGV.last =~ /\.(yaml|yml)/

        ARGV.find {|a| a.match(/\.(yml|yaml)/)}
      end

      # Creates an instance of the playbook
      #
      # @param file [String] path to a playbook yaml
      # @return [Util::Playbook]
      def playbook(file, loglevel=nil)
        unless File.exist?(file)
          raise("Cannot find supplied playbook file %s" % file)
        end

        Util.loadclass("MCollective::Util::Playbook")
        playbook = Util::Playbook.new(loglevel)
        playbook.from_hash(YAML.load_file(file))
        playbook
      end

      # Adds the playbook inputs as CLI options before starting the app
      def run
        if playbook_file = pre_parse_find_yaml
          configuration[:__playbook_file] = playbook_file

          if ARGV.include?("run")
            playbook(playbook_file).add_cli_options(self, true)
          else
            playbook(playbook_file).add_cli_options(self, false)
          end
        end

        # Hackily done here to force it below the playbook options
        self.class.option :__report,
                          :arguments => ["--report"],
                          :description => "Produce a report in YAML format",
                          :default => false,
                          :type => :boolean

        self.class.option :__report_file,
                          :arguments => ["--report-file FILE"],
                          :description => "Override the default file name for the report",
                          :type => String

        self.class.option :__loglevel,
                          :arguments => ["--loglevel LEVEL"],
                          :description => "Override the loglevel set in the playbook (debug, info, warn, error, fatal)",
                          :type => String,
                          :validate => ->(level) { ["error", "fatal", "debug", "warn", "info"].include?(level) }

        super
      end

      def post_option_parser(configuration)
        if ARGV.length >= 1
          configuration[:__command] = ARGV.shift
        else
          abort("Please specify a command, valid commands are: %s" % valid_commands.join(", "))
        end
      end

      # Validates the configuration
      #
      # @return [void]
      def validate_configuration(configuration)
        abort("Please specify a playbook to run") unless configuration[:__playbook_file]

        if options[:verbose] && !configuration.include?(:loglevel)
          configuration[:__loglevel] = "debug"
        end
      end

      # List of valid commands this application respond to
      #
      # @return [Array<String>] like `plan` and `run`
      def valid_commands
        methods.grep(/_command$/).map {|c| c.to_s.gsub("_command", "")}
      end

      def show_report_summary(report)
        puts
        puts "Summary for %s %s started at %s" % [
          Util.colorize(:bold, report["playbook"]["name"]),
          Util.colorize(:bold, report["playbook"]["version"]),
          Util.colorize(:bold, report["report"]["timestamp"])
        ]
        puts
        puts "Overall outcome: %s" % [report["report"]["success"] ? Util.colorize(:green, "success") : Util.colorize(:red, "failed")]
        puts "      Tasks Ran: %s" % [Util.colorize(:bold, report["metrics"]["task_count"])]
        puts "       Run Time: %s seconds" % [Util.colorize(:bold, report["metrics"]["run_time"].round(2))]
        puts
      end

      def run_command
        pb_config = configuration.clone
        pb_config.keys.each {|k| k.to_s.start_with?("__") && pb_config.delete(k)}

        pb = playbook(configuration[:__playbook_file], configuration[:__loglevel])

        if configuration[:__report]
          # windows can't have : in file names, ffs
          report_name = configuration.fetch(:__report_file, "playbook-%s-%s.yaml" % [pb.name, pb.report.timestamp.strftime("%F_%H-%M-%S")])

          if File.exist?(report_name)
            abort("Could not write report the file %s: it already exists" % [report_name])
          end

          begin
            report_file = File.open(report_name, "w")
          rescue
            abort("Could not write report the file %s: it can not be created: %s: %s" % [report_name, $!.class, $!.to_s])
          end
        end

        report = pb.run!(pb_config)

        show_report_summary(report)

        if configuration[:__report]
          report_file.print report.to_yaml
          puts
          puts "Report saved to %s" % report_name
        end

        report["report"]["success"] ? exit(0) : exit(1)
      end

      def show_command
        disconnect

        puts YAML.dump(YAML.load_file(configuration[:__playbook_file]))
      end

      def main
        send("%s_command" % configuration[:__command])
      end
    end
  end
end

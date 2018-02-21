module MCollective
  class Application
    class Playbook < Application
      description "Choria Playbook Runner"

      usage <<-USAGE
  mco playbook [OPTIONS] <ACTION> <PLAYBOOK>

  The ACTION can be one of the following:

    run       - run the playbook as your local user

  The PLAYBOOK is a YAML file or Puppet Plan describing the
  tasks

  Passing --help as well as a PLAYBOOK argument will show
  flags and help related to the specific playbook.

  Any inputs to the playbook should be given on the CLI.

  A report can be produced using the --report argument
  when running a playbook
  USAGE

      exclude_argument_sections "common", "filter", "rpc"

      def pre_parse_modulepath
        words = Shellwords.shellwords(ARGV.join(" "))
        words.each_with_index do |word, idx|
          if word == "--modulepath"
            configuration[:__modulepath] = words[idx + 1]
            break
          end
        end
      end

      # Playbook should be given right after the command, this finds the value after the command
      #
      # @return [String,nil]
      def pre_parse_find_playbook
        commands = Regexp.union(valid_commands)

        cmd_idx = ARGV.index {|a| a.match(commands)}
        return nil unless cmd_idx

        pb = ARGV[cmd_idx + 1]

        pb if pb =~ Regexp.union(/(yaml|yml)\Z/, /\A([a-z][a-z0-9_]*)?(::[a-z][a-z0-9_]*)*\Z/)
      end

      # Determines the playbook type from its name
      #
      # @return [:yaml, :plan]
      def playbook_type(playbook_name=nil)
        playbook_name ||= configuration[:__playbook]

        return :yaml if playbook_name =~ /(yml|yaml)$/

        :plan
      end

      # Creates an instance of the playbook
      #
      # @param file [String] path to a playbook yaml
      # @return [Util::Playbook]
      def playbook(file, loglevel=nil)
        if playbook_type(file) == :yaml
          unless File.exist?(file)
            raise("Cannot find supplied playbook file %s" % file)
          end

          Util.loadclass("MCollective::Util::Playbook")
          playbook = Util::Playbook.new(loglevel)
          playbook.from_hash(YAML.load_file(file))
          playbook
        else
          require "mcollective/util/bolt_support"
          runner = Util::BoltSupport::PlanRunner.new(
            file,
            configuration[:__tmpdir],
            configuration[:__modulepath] || Dir.pwd,
            configuration[:__loglevel] || "info"
          )

          raise("Cannot find supplied plan %s" % file) unless runner.exist?

          runner
        end
      end

      # Adds the playbook inputs as CLI options before starting the app
      def run
        pre_parse_modulepath

        Dir.mktmpdir("choria") do |dir|
          configuration[:__tmpdir] = dir

          if playbook_name = pre_parse_find_playbook
            configuration[:__playbook] = playbook_name
            playbook(playbook_name).add_cli_options(self, false)
          end

          # Hackily done here to force it below the playbook options
          self.class.option :__json_input,
                            :arguments => ["--input INPUT"],
                            :description => "JSON input to pass to the task",
                            :required => false,
                            :type => String

          self.class.option :__modulepath,
                            :arguments => ["--modulepath PATH"],
                            :description => "Path to find Puppet module when using the Plan DSL",
                            :type => String

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
      end

      def post_option_parser(configuration)
        if ARGV.length >= 1
          configuration[:__command] = ARGV.shift
        else
          abort("Please specify a command, valid commands are: %s" % valid_commands.join(", "))
        end

        if input = configuration[:__json_input]
          result = {}

          if input.start_with?("@")
            input.sub!("@", "")
            result = JSON.parse(File.read(input)) if input.end_with?("json")
            result = YAML.safe_load(File.read(input)) if input.end_with?("yaml")
          else
            result = JSON.parse(input)
          end

          configuration.merge!(result)
        end
      end

      # Validates the configuration
      #
      # @return [void]
      def validate_configuration(configuration)
        abort("Please specify a playbook to run") unless configuration[:__playbook]

        if options[:verbose] && !configuration.include?(:loglevel)
          configuration[:__loglevel] = "debug"
        end

        if configuration[:__report] && playbook_type == :plan
          abort("Reports are only supported for YAML playbooks")
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
        pb_config.delete_if {|k, _| k.to_s.start_with?("__")}

        pb = playbook(configuration[:__playbook], configuration[:__loglevel])

        run_playbook(pb, pb_config) if playbook_type == :yaml
        run_plan(pb, pb_config)
      end

      def run_plan(pb, pb_config)
        startime = Time.now

        success = true

        result = pb.run!(pb_config)
      rescue
        success = false
      ensure
        disconnect

        endtime = Time.now

        color = :green
        msg = "OK"

        unless success
          color = :red
          msg = "FAILED"
        end

        puts
        puts "Plan %s ran in %.2f seconds: %s" % [
          Util.colorize(:bold, configuration[:__playbook]),
          endtime - startime,
          Util.colorize(color, msg)
        ]

        unless result.nil?
          puts
          puts "Result: "
          puts
          puts Util.align_text(JSON.pretty_generate(result), 10000)
          puts
        end

        success ? exit(0) : exit(1)
      end

      def run_playbook(pb, pb_config)
        Log.warn("YAML playbooks on the command line are deprecated and will be removed soon, please use Plan DSL playbooks")

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

      def main
        send("%s_command" % configuration[:__command])
      end
    end
  end
end

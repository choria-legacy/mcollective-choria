module MCollective
  class Application
    class Playbook < Application
      description "Choria Playbook Runner"

      usage <<-USAGE
  mco playbook [OPTIONS] <ACTION> <PLAYBOOK>

  The ACTION can be one of the following:

    run       - run the playbook as your local user

  The PLAYBOOK Puppet Plan describing the tasks to perform

  Passing --help as well as a PLAYBOOK argument will show
  flags and help related to the specific playbook.

  Any inputs to the playbook should be given on the CLI.
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

        pb if pb =~ /\A([a-z][a-z0-9_]*)?(::[a-z][a-z0-9_]*)*\Z/
      end

      # Creates an instance of the plan runner
      #
      # @param plan [String] the name of a plan
      # @return [Util::BoltSupport::PlanRunner]
      def runner(plan, loglevel=nil)
        unless configuration[:__modulepath]
          configuration[:__modulepath] = File.expand_path("~/.puppetlabs/etc/code/modules")
        end

        require "mcollective/util/bolt_support"
        runner = Util::BoltSupport::PlanRunner.new(
          plan,
          configuration[:__tmpdir],
          configuration[:__modulepath] || Dir.pwd,
          configuration[:__loglevel] || "info"
        )

        unless runner.exist?
          STDERR.puts("Cannot find supplied Playbook %s" % plan)
          STDERR.puts
          STDERR.puts("Module Path:")
          STDERR.puts
          STDERR.puts(Util.align_text(configuration[:__modulepath].split(":").join("\n")))
          exit(1)
        end

        runner
      end

      # Adds the playbook inputs as CLI options before starting the app
      def run
        pre_parse_modulepath

        Dir.mktmpdir("choria") do |dir|
          configuration[:__tmpdir] = dir

          if playbook_name = pre_parse_find_playbook
            configuration[:__playbook] = playbook_name
            runner(playbook_name).add_cli_options(self, false)
          end

          # Hackily done here to force it below the playbook options
          self.class.option :__json_input,
                            :arguments => ["--input INPUT"],
                            :description => "JSON input to pass to the task",
                            :required => false,
                            :type => String

          self.class.option :__modulepath,
                            :arguments => ["--modulepath PATH"],
                            :description => "Path to find Puppet module when using the Playbook DSL",
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
      end

      # List of valid commands this application respond to
      #
      # @return [Array<String>] like `plan` and `run`
      def valid_commands
        methods.grep(/_command$/).map {|c| c.to_s.gsub("_command", "")}
      end

      def run_command
        pb_config = configuration.clone
        pb_config.delete_if {|k, _| k.to_s.start_with?("__")}

        pb = runner(configuration[:__playbook], configuration[:__loglevel])

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
        puts "Playbook %s ran in %.2f seconds: %s" % [
          Util.colorize(:bold, configuration[:__playbook]),
          endtime - startime,
          Util.colorize(color, msg)
        ]

        if result
          puts
          puts "Result: "
          puts
          puts Util.align_text(JSON.pretty_generate(result), 10000)
          puts
        end

        success ? exit(0) : exit(1)
      end

      def main
        send("%s_command" % configuration[:__command])
      end
    end
  end
end

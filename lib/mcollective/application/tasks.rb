module MCollective
  class Application
    class Tasks < Application
      description "Puppet Task Orchestrator"

      usage <<-USAGE

    mco tasks [--detail]
    mco tasks <TASK NAME>
    mco tasks run <TASK NAME> [OPTIONS]
    mco tasks status <REQUEST> [FLAGS]

 The Task Orchestrator is designed to provide a consistent
 management environment for Puppet Tasks.

 It will download tasks from your Puppet Server onto all nodes
 and after verifying they were able to correctly download the
 same task across the entire fleet will run the task.

 Tasks are run in the background, the CLI can wait for up to 60
 seconds for your task to complete and show the status or you
 can use the status comment to review a completed task later.
      USAGE

      exclude_argument_sections "rpc"

      def post_option_parser(configuration)
        configuration[:__command] = ARGV.shift || "list"
      end

      def list_options
        self.class.option :__detail,
                          :arguments => ["--detail"],
                          :description => "Show command descriptions",
                          :default => false,
                          :type => :boolean
      end

      def status_options
        application_options[:usage].clear

        self.class.usage <<-USAGE

    mco tasks status <REQUEST> [FLAGS]

 Retrieves the status for a task you previously requested.  It can be running or completed.

 By default only failed exuecutions are shown, use --verbose to see them all.

        USAGE

        self.class.option :__summary,
                          :arguments => ["--summary"],
                          :description => "Only show a overall summary of the task",
                          :default => false,
                          :type => :boolean

        self.class.option :__metadata,
                          :arguments => ["--metadata"],
                          :description => "Only show task metadata for each node",
                          :default => false,
                          :type => :boolean

        self.class.option :__json_format,
                          :arguments => ["--json"],
                          :description => "Display results in JSON format",
                          :default => false,
                          :type => :boolean
      end

      def run_options # rubocop:disable Metrics/MethodLength
        application_options[:usage].clear

        self.class.usage <<-USAGE

    mco tasks run <TASK NAME> [OPTIONS]

 Runs a task in the background and wait up to 50 seconds for it to complete.

 Task inputs are handled using --argument=value for basic String, Numeric and Boolean
 types, others can be passed using --input

 Input can also be read from a file using "--input @file.json" or "--input @file.yaml".

 For complex data types like Hashes, Arrays or Variants you have to supply input
 as YAML or JSON.

 Once a task is run the task ID will be displayed which can later be used with
 the "mco tasks status" command to extract results.

Examples:

    Run myapp::upgrade task in the background and wait for it to complete:

       mco tasks run myapp::upgrade --version 1.0.0

    Run myapp::upgrade task in the background and return immediately:

       mco tasks run myapp::upgrade --version 1.0.0 --background

    Supply complex data input to the task:

       Should input be given on both the CLI arguments and a file
       the CLI arguments will override the file

       mco tasks run myapp::upgrade --input @input.json
       mco tasks run myapp::upgrade --input @input.yaml
       mco tasks run myapp::upgrade --version 1.0.0 --input \\
          '{"source": {
            "url": "http://repo/archive-1.0.0.tgz",
            "hash": "68b329da9893e34099c7d8ad5cb9c940"}}'

        USAGE

        task = ARGV[1]

        abort("Please specify a task to run") unless task

        cli.create_task_options(task, "production", self)

        self.class.option :__summary,
                          :arguments => ["--summary"],
                          :description => "Only show a overall summary of the task",
                          :default => false,
                          :type => :boolean

        self.class.option :__background,
                          :arguments => ["--background"],
                          :description => "Do not wait for the task to complete",
                          :default => false,
                          :type => :boolean

        self.class.option :__json_input,
                          :arguments => ["--input INPUT"],
                          :description => "JSON input to pass to the task",
                          :required => false,
                          :type => String

        self.class.option :__batch_size,
                          :arguments => ["--batch SIZE"],
                          :description => "Run tasks on nodes in batches",
                          :required => false,
                          :type => String

        self.class.option :__batch_sleep,
                          :arguments => ["--batch-sleep SECONDS"],
                          :description => "Time to sleep between invocations of batches of nodes",
                          :required => false,
                          :default => 1,
                          :type => Integer
      end

      def say(msg="")
        puts(msg) unless configuration[:__json_format]
      end

      def run_command
        task = ARGV.shift

        input = cli.task_input(configuration)

        say("Retrieving task metadata for task %s from the Puppet Server" % task)

        begin
          meta = cli.task_metadata(task, "production")
        rescue
          abort($!.to_s)
        end

        cli.transform_hash_strings(meta, input)
        cli.validate_task_input(task, meta, input)

        say("Attempting to download and run task %s on %d nodes" % [Util.colorize(:bold, task), bolt_tasks.discover.size])
        say

        download_files(task, meta["files"])

        request = {
          :task => task,
          :files => meta["files"].to_json
        }

        request[:input] = input.to_json if input

        if configuration[:__background]
          puts("Starting task %s in the background" % [Util.colorize(:bold, task)])

          if configuration[:__batch_size]
            bolt_tasks.batch_size = configuration[:__batch_size]
            bolt_tasks.batch_sleep_time = configuration[:__batch_sleep]
            bolt_tasks.progress = true
          end

          printrpc bolt_tasks.run_no_wait(request)
          printrpcstats

          if bolt_tasks.stats.okcount > 0
            puts
            puts("Request detailed status for the task using 'mco tasks status %s'" % [Util.colorize(:bold, bolt_tasks.stats.requestid)])
          end
        else
          say("Running task %s and waiting up to %s seconds for it to complete" % [
            Util.colorize(:bold, task),
            Util.colorize(:bold, bolt_tasks.ddl.meta[:timeout])
          ])

          request_and_report(:run_and_wait, request)
        end
      ensure
        reset_client!
      end

      def download_files(task, files)
        bolt_tasks.batch_size = 50
        bolt_tasks.batch_sleep_time = 1

        failed = false

        downloads = []
        cnt = bolt_tasks.discover.size
        idx = 0

        bolt_tasks.download(:environment => "production", :task => task, :files => files.to_json) do |_, s|
          unless configuration[:__json_format]
            print(cli.twirl("Downloading and verifying %d file(s) from the Puppet Server to all nodes:" % [files.size], cnt, idx + 1))
            puts if cnt == idx + 1
          end

          idx += 1
          downloads << s
        end

        downloads.select {|d| d[:statuscode] > 0}.each_with_index do |download, i|
          failed = true
          puts if i == 0
          puts("   %s: %s" % [Util.colorize(:red, "Could not download files onto %s" % download[:sender]), download[:statusmsg]])
        end

        unless bolt_tasks.stats.noresponsefrom.empty?
          puts
          puts bolt_tasks.stats.no_response_report
          failed = true
        end

        if failed
          puts
          abort("Could not download the task %s onto all nodes" % task)
        end
      end

      def status_command
        taskid = ARGV.shift

        abort("Please specify a task id to display") unless taskid

        if configuration[:__metadata]
          unless options[:verbose]
            say("Requesting task metadata for request %s" % Util.colorize(:bold, taskid))
          end

          bolt_tasks.task_status(:task_id => taskid).each do |status|
            cli.print_result_metadata(status)
          end

          cli.print_rpc_stats(bolt_tasks.stats)
        else
          unless options[:verbose]
            say("Requesting task status for request %s, showing failures only pass --verbose for all output" % Util.colorize(:bold, taskid))
          end

          request_and_report(:task_status, {:task_id => taskid}, taskid)
        end
      end

      def request_and_report(action, arguments, taskid=nil) # rubocop:disable Metrics/MethodLength
        task_not_known_nodes = 0
        wrapper_failure = 0
        completed_nodes = 0
        running_nodes = 0
        runtime = 0.0
        success_nodes = 0
        fail_nodes = 0
        progress = configuration[:__summary] || configuration[:__batch_size] ? RPC::Progress.new : nil
        cnt = 0
        expected = bolt_tasks.discover.size
        task_names = []
        callers = []

        if configuration[:__batch_size]
          bolt_tasks.batch_size = configuration[:__batch_size]
          bolt_tasks.batch_sleep_time = configuration[:__batch_sleep]
        end

        say

        bolt_tasks.send(action, arguments) do |_, reply|
          status = reply[:data]

          if reply[:statuscode] == 3
            fail_nodes += 1
            task_not_known_nodes += 1
          elsif status[:exitcode] == 0
            status[:completed] ? completed_nodes += 1 : running_nodes += 1
            runtime += status[:runtime]
            reply[:statuscode] == 0 ? success_nodes += 1 : fail_nodes += 1
          elsif reply[:statuscode] == 5
            wrapper_failure += 1
            fail_nodes += 1
          else
            fail_nodes += 1
          end

          task_names << status[:task] if status[:task]
          callers << status[:callerid] if status[:callerid]

          if progress
            print(progress.twirl(cnt + 1, expected))

            say if cnt + 1 == expected
          else
            cli.print_result(reply)
          end

          cnt += 1
        end

        taskid ||= bolt_tasks.stats.requestid

        callers.compact!
        callers.uniq!
        task_names.compact!
        task_names.uniq!

        say

        cli.print_task_summary(
          taskid,
          task_names,
          callers,
          completed_nodes,
          running_nodes,
          task_not_known_nodes,
          wrapper_failure,
          success_nodes,
          fail_nodes,
          runtime,
          bolt_tasks.stats
        )
      ensure
        reset_client!
      end

      def list_command
        cli.show_task_list("production", configuration[:__detail])
      end

      def run
        command = ARGV[0]
        command = "list" unless valid_commands.include?(command)

        send("%s_options" % command)

        super
      end

      def show_task_help(task)
        cli.show_task_help(task, "production")
      end

      def bolt_tasks
        @__bolt_tasks ||= rpcclient("bolt_tasks")
      end

      def reset_client!
        bolt_tasks.batch_size = 0
        bolt_tasks.progress = options[:verbose]
      end

      def extract_environment_from_argv
        idx = ARGV.index("--environment")

        return "production" unless idx

        ARGV[idx + 1]
      end

      def valid_commands
        methods.grep(/_command$/).map {|c| c.to_s.gsub("_command", "")}
      end

      def choria
        Util.loadclass("MCollective::Util::Choria")

        @__choria ||= Util::Choria.new
      end

      def tasks_support
        @__tasks ||= choria.tasks_support
      end

      def cli
        format = configuration[:__json_format] ? :json : :default

        if options
          @__cli ||= tasks_support.cli(format, options[:verbose])
        else
          tasks_support.cli(format, false)
        end
      end

      def main
        if valid_commands.include?(configuration[:__command])
          send("%s_command" % configuration[:__command])
        else
          show_task_help(configuration[:__command])
        end
      end
    end
  end
end

module MCollective
  class Application
    class Tasks < Application
      description "Bolt Task Orchestrator"

      usage <<-USAGE

  mco tasks [--detail]
  mco tasks <TASK NAME>
  mco tasks run <TASK NAME> [OPTIONS]
  mco tasks status <REQUEST> [OPTIONS]
      USAGE

      option :__environment,
             :arguments => ["--environment"],
             :description => "Environment to retrieve tasks from",
             :default => "production",
             :type => String

      exclude_argument_sections "common", "rpc"

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
        self.class.option :__summary,
                          :arguments => ["--summary"],
                          :description => "Only show a overall summary of the task",
                          :default => false,
                          :type => :boolean
      end

      def run_options
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
                          :required => true,
                          :type => String

        self.class.option :__json_input,
                          :arguments => ["--input INPUT"],
                          :description => "JSON input to pass to the task",
                          :required => true,
                          :type => String
      end

      def run_command
        task = ARGV.shift
        abort("Please specify a task to run") unless task

        puts("Attempting to download and run task %s on %d nodes" % [Util.colorize(:bold, task), bolt_task.discover.size])
        puts
        puts("Retrieving task metadata for task %s from the Puppet Server" % task)

        begin
          meta = tasks_support.task_metadata(task, configuration[:__environment])
        rescue
          abort($!.to_s)
        end

        download_files(task, meta["files"])

        request = {
          :task => task,
          :files => meta["files"].to_json,
          :input => configuration[:__json_input]
        }

        puts

        if configuration[:__background]
          puts("Starting task %s in the background" % [Util.colorize(:bold, task)])
          printrpc bolt_task.run_no_wait(request)
          printrpcstats

          if bolt_task.stats.okcount > 0
            puts
            puts("Request detailed status for the task using 'mco tasks status %s'" % [Util.colorize(:bold, bolt_task.stats.requestid)])
          end
        else
          puts("Running task %s and waiting up to %s seconds for it to complete" % [
            Util.colorize(:bold, task),
            Util.colorize(:bold, bolt_task.ddl.meta[:timeout])
          ])

          request_and_report(:run_and_wait, request)
        end
      end

      def download_files(task, files)
        original_batch_size = bolt_task.batch_size
        bolt_task.batch_size = 50

        puts("Downloading and verifying %d file(s) from the Puppet Server to all Nodes" % [files.size])

        failed = false

        downloads = bolt_task.download(:environment => configuration[:__environment], :task => task, :files => files.to_json)

        downloads.select {|d| d[:statuscode] > 0}.each_with_index do |download, idx|
          puts if idx == 0
          failed = true
          puts("   %s: %s" % [Util.colorize(:red, "Could not download files onto %s" % download[:sender]), download[:statusmsg]])
        end

        unless bolt_task.stats.noresponsefrom.empty?
          puts
          puts bolt_task.stats.no_response_report
          failed = true
        end

        if failed
          puts
          abort("Could not download the task %s onto all nodes" % task)
        end
      ensure
        bolt_task.batch_size = original_batch_size
      end

      def status_command
        taskid = ARGV.shift

        abort("Please specify a task id to display") unless taskid

        unless options[:verbose]
          puts("Requesting task status for request %s, showing failures only pass --verbose for all output" % Util.colorize(:bold, taskid))
        end

        request_and_report(:task_status, {:task_id => taskid}, taskid)
      end

      def print_result(result)
        status = result[:data]

        if result[:statuscode] != 0
          puts("%-40s %s" % [
            Util.colorize(:red, result[:sender]),
            Util.colorize(:yellow, result[:statusmsg])
          ])

          puts("   %s" % status[:stdout])
          puts("   %s" % status[:stderr]) if status[:stderr]
        elsif result[:statuscode] == 0 && options[:verbose]
          puts(result[:sender])
          puts("   %s" % status[:stdout])
          puts("   %s" % status[:stderr]) if status[:stderr]
        end
      end

      def request_and_report(action, arguments, taskid=nil)
        task_not_known_nodes = 0
        wrapper_failure = 0
        completed_nodes = 0
        running_nodes = 0
        runtime = 0.0
        success_nodes = 0
        fail_nodes = 0
        progress = configuration[:__summary] ? RPC::Progress.new : nil
        cnt = 0
        expected = bolt_task.discover.size

        puts

        bolt_task.send(action, arguments) do |_, s|
          status = s[:data]

          if status[:exitcode] == 3
            task_not_known_nodes += 1
          elsif status[:exitcode] == 0
            status[:completed] ? completed_nodes += 1 : running_nodes += 1
            runtime += status[:runtime]
            status[:exitcode] == 0 ? success_nodes += 1 : fail_nodes += 1
          else
            wrapper_failure += 1
            fail_nodes += 1
          end

          if configuration[:__summary]
            print(progress.twirl(cnt + 1, expected))
          else
            print_result(s)
          end

          cnt += 1
        end

        taskid ||= bolt_task.stats.requestid

        puts("Summary for task %s" % [Util.colorize(:bold, taskid)])
        puts
        puts("                       Completed: %d" % completed_nodes)
        puts("                         Running: %s" % (running_nodes > 0 ? Util.colorize(:yellow, running_nodes) : running_nodes))
        puts("                    Unknown Task: %s" % Util.colorize(:red, task_not_known_nodes)) if task_not_known_nodes > 0
        puts("                 Wrapper Failure: %s" % Util.colorize(:red, wrapper_failure)) if wrapper_failure > 0
        puts
        puts("                      Successful: %d" % success_nodes)
        puts("                          Failed: %s" % (fail_nodes > 0 ? Util.colorize(:red, fail_nodes) : fail_nodes))
        puts
        puts("                Average Run Time: %.2fs" % [runtime / (running_nodes + completed_nodes)])

        if bolt_task.stats.noresponsefrom.empty?
          puts
          puts bolt_task.stats.no_response_report
        end

        if running_nodes > 0
          puts
          puts("%s nodes are still running, use 'mco tasks status %s' to check on them later" % [Util.colorize(:bold, running_nodes), taskid])
        end
      end

      def list_command
        puts "Known tasks in the %s environment" % configuration[:__environment]
        puts

        print("Retrieving tasks....")
        known_tasks = task_list(configuration[:__detail], configuration[:__environment])

        print("\r")

        if configuration[:__detail]
          known_tasks.each do |name, description|
            puts "  %-20s %s" % [name, description]
          end

          puts
          puts("Use mco task <TASK> to see task help")
        else
          known_tasks.keys.in_groups_of(3) do |tasks|
            puts "  %s" % tasks.compact.map {|t| "%-20s" % t }.join(" ")
          end

          puts
          puts("Use mco task <TASK> to see task help")
          puts("Specify --detail to see task descriptions")
        end
      end

      def run
        command = ARGV[0]
        command = "list" unless valid_commands.include?(command)

        send("%s_options" % command)

        super
      end

      def task_list(descriptions, environment)
        tasks = {}

        known_tasks = tasks_support.tasks(environment)

        known_tasks.each do |task|
          description = nil

          if descriptions
            meta = tasks_support.task_metadata(task["name"], environment)
            description = meta["metadata"]["description"]
          end

          tasks[task["name"]] = description
        end

        tasks
      end

      def show_task_help(task)
        puts("Retrieving task metadata for task %s from the Puppet Server" % task)

        begin
          meta = tasks_support.task_metadata(task, configuration[:__environment])
        rescue
          abort($!.to_s)
        end

        puts

        puts("%s - %s" % [Util.colorize(:bold, task), meta["metadata"]["description"]])
        puts

        if meta["metadata"]["parameters"].empty?
          puts("The task takes no parameters or have none defined")
          puts
        else
          puts("Task Parameters:")

          meta["metadata"]["parameters"].sort_by {|n, _| n}.each do |name, details|
            puts("  %-30s %s (%s)" % [name, details["description"], details["type"]])
          end
        end

        puts
        puts "Task Files:"
        meta["files"].each do |file|
          puts("  %-30s %s bytes" % [file["filename"], file["size_bytes"]])
        end

        puts
        puts("Use 'mco tasks run %s' to run this task" % [task])
      end

      def bolt_task
        @__bolt_task ||= rpcclient("bolt_task")
      end

      def valid_commands
        methods.grep(/_command$/).map {|c| c.to_s.gsub("_command", "")}
      end

      def choria
        Util.loadclass("MCollective::Util::Choria")

        @__choria ||= Util::Choria.new
      end

      def tasks_support
        @__tasks || choria.tasks_support
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

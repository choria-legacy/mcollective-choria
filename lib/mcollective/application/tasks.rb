module MCollective
  class Application
    class Tasks < Application
      description "Puppet Task Orchestrator"

      usage <<-USAGE

    mco tasks [--detail]
    mco tasks <TASK NAME>
    mco tasks run <TASK NAME> [OPTIONS]
    mco tasks status <REQUEST> [FLAGS]

 The Bolt Task Orchestrator is designed to provide a consistent
 management environment for Bolt Tasks.

 It will download tasks from your Puppet Server onto all nodes
 and after verifying they were able to correctly download the
 same task across the entire fleet will run the task.

 Tasks are run in the background, the CLI can wait for up to 60
 seconds for your task to complete and show the status or you
 can use the status comment to review a completed task later.
      USAGE

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

        self.class.option :__environment,
                          :arguments => ["--environment"],
                          :description => "Environment to retrieve tasks from",
                          :default => "production",
                          :type => String
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

        self.class.option :__environment,
                          :arguments => ["--environment"],
                          :description => "Environment to retrieve tasks from",
                          :default => "production",
                          :type => String
      end

      def run_options
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

        create_task_options(task, extract_environment_from_argv)

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

        self.class.option :__environment,
                          :arguments => ["--environment"],
                          :description => "Environment to retrieve tasks from",
                          :default => "production",
                          :type => String
      end

      def run_command
        task = ARGV.shift

        # here to test it early and fail fast
        input = task_input

        puts("Attempting to download and run task %s on %d nodes" % [Util.colorize(:bold, task), bolt_task.discover.size])
        puts
        puts("Retrieving task metadata for task %s from the Puppet Server" % task)

        begin
          meta = task_metadata(task, configuration[:__environment])
        rescue
          abort($!.to_s)
        end

        download_files(task, meta["files"])

        request = {
          :task => task,
          :files => meta["files"].to_json
        }

        request[:input] = input if input

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

        failed = false

        downloads = []
        cnt = bolt_task.discover.size
        idx = 0

        bolt_task.download(:environment => configuration[:__environment], :task => task, :files => files.to_json) do |_, s|
          twirl("Downloading and verifying %d file(s) from the Puppet Server to all nodes:" % [files.size], cnt, idx + 1)
          idx += 1
          downloads << s
        end

        downloads.select {|d| d[:statuscode] > 0}.each_with_index do |download, i|
          puts if i == 0
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

        if configuration[:__metadata]
          unless options[:verbose]
            puts("Requesting task metadata for request %s" % Util.colorize(:bold, taskid))
          end

          bolt_task.task_status(:task_id => taskid).each do |status|
            result = status.results

            if [0, 1].include?(result[:statuscode])
              if result[:data][:exitcode] == 0
                puts("  %-40s %s" % [result[:sender], Util.colorize(:green, result[:data][:exitcode])])
              else
                puts("  %-40s %s" % [result[:sender], Util.colorize(:red, result[:data][:exitcode])])
              end

              puts("    %s by %s at %s" % [
                Util.colorize(:bold, result[:data][:task]),
                result[:data][:callerid],
                Time.at(result[:data][:start_time]).utc.strftime("%F %T")
              ])

              puts("    completed: %s runtime: %s stdout: %s stderr: %s" % [
                result[:data][:completed] ? Util.colorize(:bold, "yes") : Util.colorize(:yellow, "no"),
                Util.colorize(:bold, "%.2f" % result[:data][:runtime]),
                result[:data][:stdout].empty? ? Util.colorize(:yellow, "no") : Util.colorize(:bold, "yes"),
                result[:data][:stderr].empty? ? Util.colorize(:bold, "no") : Util.colorize(:red, "yes")
              ])
            elsif result[:statuscode] == 3
              puts("  %-40s %s" % [result[:sender], Util.colorize(:yellow, "Unknown Task")])
            else
              puts("  %-40s %s" % [result[:sender], Util.colorize(:yellow, result[:statusmsg])])
            end

            puts
          end

          printrpcstats
        else
          unless options[:verbose]
            puts("Requesting task status for request %s, showing failures only pass --verbose for all output" % Util.colorize(:bold, taskid))
          end

          request_and_report(:task_status, {:task_id => taskid}, taskid)
        end
      end

      def print_result(result)
        status = result[:data]
        stdout_text = status[:stdout] || ""

        unless options[:verbose]
          begin
            stdout_text = JSON.parse(status[:stdout])
            stdout_text.delete("_error")
            stdout_text = stdout_text.to_json
            stdout_text = nil if stdout_text == "{}"
          rescue # rubocop:disable Lint/HandleExceptions
          end
        end

        if result[:statuscode] != 0
          puts("%-40s %s" % [
            Util.colorize(:red, result[:sender]),
            Util.colorize(:yellow, result[:statusmsg])
          ])

          puts("   %s" % stdout_text) if stdout_text
          puts("   %s" % status[:stderr]) unless ["", nil].include?(status[:stderr])
          puts
        elsif result[:statuscode] == 0 && options[:verbose]
          puts(result[:sender])
          puts("   %s" % stdout_text) if stdout_text
          puts("   %s" % status[:stderr]) unless ["", nil].include?(status[:stderr])
          puts
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
        progress = configuration[:__summary] ? RPC::Progress.new : nil
        cnt = 0
        expected = bolt_task.discover.size
        task_names = []
        callers = []

        puts

        bolt_task.send(action, arguments) do |_, reply|
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

          if configuration[:__summary]
            print(progress.twirl(cnt + 1, expected))
          else
            print_result(reply)
          end

          cnt += 1
        end

        taskid ||= bolt_task.stats.requestid

        callers.compact!
        callers.uniq!
        task_names.compact!
        task_names.uniq!

        if callers.size > 1 || task_names.size > 1
          puts
          puts("%s received more than 1 task name or caller name for this task, this should not happen" % Util.colorize(:red, "WARNING"))
          puts("happen in normal operations and might indicate forged requests were made or cache corruption.")
          puts
        end

        puts("Summary for task %s" % [Util.colorize(:bold, taskid)])
        puts
        puts("                       Task Name: %s" % task_names.join(","))
        puts("                          Caller: %s" % callers.join(","))
        puts("                       Completed: %s" % (completed_nodes > 0 ? Util.colorize(:green, completed_nodes) : Util.colorize(:yellow, completed_nodes)))
        puts("                         Running: %s" % (running_nodes > 0 ? Util.colorize(:yellow, running_nodes) : Util.colorize(:green, running_nodes)))
        puts("                    Unknown Task: %s" % Util.colorize(:red, task_not_known_nodes)) if task_not_known_nodes > 0
        puts("                 Wrapper Failure: %s" % Util.colorize(:red, wrapper_failure)) if wrapper_failure > 0
        puts
        puts("                      Successful: %s" % (success_nodes > 0 ? Util.colorize(:green, success_nodes) : Util.colorize(:red, success_nodes)))
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

        print("Retrieving tasks....")

        known_tasks = tasks_support.tasks(environment)

        known_tasks.each_with_index do |task, idx|
          description = nil

          if descriptions
            twirl("Retrieving tasks....", known_tasks.size, idx)
            meta = task_metadata(task["name"], environment)
            description = meta["metadata"]["description"]
          end

          tasks[task["name"]] = description
        end

        tasks
      end

      def show_task_help(task)
        puts("Retrieving task metadata for task %s from the Puppet Server" % task)

        begin
          meta = task_metadata(task, configuration[:__environment])
        rescue
          abort($!.to_s)
        end

        puts

        puts("%s - %s" % [Util.colorize(:bold, task), meta["metadata"]["description"]])
        puts

        if meta["metadata"]["parameters"].nil? || meta["metadata"]["parameters"].empty?
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

      # Converts a Puppet type into something mcollective understands
      #
      # This is inevitably hacky by its nature, there is no way for me to
      # parse the types.  PAL might get some helpers for this but till then
      # this is going to have to be best efforts.
      #
      # When there is a too complex situation users can always put in --input
      # and some JSON to work around it until something better comes around
      #
      # @param type [String] a puppet type
      def puppet_type_to_ruby(type)
        array = false
        required = true

        if type =~ /Optional\[(.+)/
          type = $1
          required = false
        end

        if type =~ /Array\[(.+)/
          type = $1
          array = true
        end

        return [Numeric, array, required] if type =~ /Integer/
        return [Numeric, array, required] if type =~ /Float/
        return [Hash, array, required] if type =~ /Hash/
        return [:boolean, array, required] if type =~ /Boolean/

        [String, array, required]
      end

      def twirl(msg, max, current)
        charset = ["▖", "▘", "▝", "▗"]
        index = current % charset.size
        char = charset[index]
        char = Util.colorize(:green, "✓") if max == current

        format = "\r%s %s  %#{@max.to_s.size}d / %d"
        print(format % [msg, char, current, max])
      end

      def bolt_task
        @__bolt_task ||= rpcclient("bolt_task")
      end

      def extract_environment_from_argv
        idx = ARGV.index("--environment")

        return "production" unless idx

        ARGV[idx + 1]
      end

      def create_task_options(task, environment)
        meta = task_metadata(task, environment)

        return if meta["metadata"]["parameters"].nil? || meta["metadata"]["parameters"].empty?

        meta["metadata"]["parameters"].sort_by {|n, _| n}.each do |name, details|
          type, array, required = puppet_type_to_ruby(details["type"])
          description = "%s (%s)" % [details["description"], details["type"]]

          properties = {
            :description => description,
            :arguments => ["--%s %s" % [name.downcase, name.upcase]],
            :type => array ? :array : type,
            :required => required
          }

          properties[:arguments] = ["--%s" % name.downcase] if type == :boolean

          self.class.option(name.intern, properties)
        end
      end

      def task_input
        result = {}

        input = configuration[:__json_input]

        if input
          input.sub!("@", "")
          result = File.read(input) if input.end_with?("json")
          result = YAML.safe_load(File.read(input)).to_json if input.end_with?("yaml")
        end

        configuration.each do |item, value|
          next if item.to_s.start_with?("__")
          result[item.to_s] = value
        end

        return result.to_json unless result.empty?

        abort("Could not parse input from --input as YAML or JSON")

        nil
      end

      def task_metadata(task, environment)
        @__metadata ||= {}

        return @__metadata[task] if @__metadata[task]

        @__metadata[task] = tasks_support.task_metadata(task, environment)
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

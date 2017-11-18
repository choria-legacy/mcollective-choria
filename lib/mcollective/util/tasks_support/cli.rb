module MCollective
  module Util
    class TasksSupport
      class CLI
        attr_reader :output

        def initialize(support, format, verbose)
          @support = support

          if format == :json
            require_relative "json_formatter"
            @output = CLI::JSONFormatter.new(self, verbose)
          else
            require_relative "default_formatter"
            @output = CLI::DefaultFormatter.new(self, verbose)
          end
        end

        # Shows the task list
        #
        # @param environment [String] the environment to query
        # @param detail [Boolean] show task descriptions
        # @param out [IO]
        def show_task_list(environment, detail, out=STDOUT)
          out.puts "Known tasks in the %s environment" % environment
          out.puts

          known_tasks = task_list(environment, detail, out)

          out.print("\r")

          padding = known_tasks.keys.map(&:size).max + 2

          if detail
            known_tasks.each do |name, description|
              out.puts "  %-#{padding}s %s" % [name, description]
            end

            out.puts
            out.puts("Use mco task <TASK> to see task help")
          else
            known_tasks.keys.in_groups_of(3) do |tasks|
              out.puts "  %s" % tasks.compact.map {|t| "%-#{padding}s" % t }.join(" ")
            end

            out.puts
            out.puts("Use mco task <TASK> to see task help")
            out.puts("Pass option --detail to see task descriptions")
          end
        end

        # Retrieves the task list
        #
        # @param environment [String] the environment to query
        # @param detail [Boolean] show task descriptions
        def task_list(environment, detail, out=STDOUT)
          tasks = {}

          out.print("Retrieving tasks....")

          known_tasks = @support.tasks(environment)

          known_tasks.each_with_index do |task, idx|
            description = nil
            if detail
              out.print(twirl("Retrieving tasks....", known_tasks.size, idx))
              meta = task_metadata(task["name"], environment)
              description = meta["metadata"]["description"]
            end

            tasks[task["name"]] = description || ""
          end

          tasks
        end

        # Creates help for a task
        #
        # @param task [String] task name
        # @param environment [String] environment to feetch task from
        # @param out [IO]
        def show_task_help(task, environment, out=STDOUT)
          out.puts("Retrieving task metadata for task %s from the Puppet Server" % task)

          begin
            meta = task_metadata(task, environment)
          rescue
            abort($!.to_s)
          end

          out.puts

          out.puts("%s - %s" % [Util.colorize(:bold, task), meta["metadata"]["description"]])
          out.puts

          if meta["metadata"]["parameters"].nil? || meta["metadata"]["parameters"].empty?
            out.puts("The task takes no parameters or have none defined")
            out.puts
          else
            out.puts("Task Parameters:")

            meta["metadata"]["parameters"].sort_by {|n, _| n}.each do |name, details|
              out.puts("  %-30s %s (%s)" % [name, details["description"], details["type"]])
            end
          end

          out.puts
          out.puts "Task Files:"
          meta["files"].each do |file|
            out.puts("  %-30s %s bytes" % [file["filename"], file["size_bytes"]])
          end

          out.puts
          out.puts("Use 'mco tasks run %s' to run this task" % [task])
        end

        # (see DefaultFormatter.print_task_summary)
        def print_task_summary(*args)
          @output.print_task_summary(*args)
        end

        # (see DefaultFormatter.print_result)
        def print_result(*args)
          @output.print_result(*args)
        end

        # (see DefaultFormatter.print_rpc_stats)
        def print_rpc_stats(*args)
          @output.print_rpc_stats(*args)
        end

        # (see DefaultFormatter.print_result_metadata)
        def print_result_metadata(*args)
          @output.print_result_metadata(*args)
        end

        # Parses the given CLI input string and creates results based on it
        #
        # @param configuration [Hash] the mcollective Application configuration
        # @return [Hash,nil]
        def task_input(configuration)
          result = {}

          input = configuration[:__json_input]

          if input && input.start_with?("@")
            input.sub!("@", "")
            result = JSON.parse(File.read(input)) if input.end_with?("json")
            result = YAML.safe_load(File.read(input)) if input.end_with?("yaml")
          else
            result = JSON.parse(input)
          end

          configuration.each do |item, value|
            next if item.to_s.start_with?("__")
            result[item.to_s] = value
          end

          return result unless result.empty?

          abort("Could not parse input from --input as YAML or JSON")

          nil
        end

        # Adds CLI options for all defined input
        #
        # @param meta [Hash] the task metadata
        # @param application [Application]
        def create_task_options(task, environment, application)
          meta = task_metadata(task, environment)

          return if meta["metadata"]["parameters"].nil? || meta["metadata"]["parameters"].empty?

          meta["metadata"]["parameters"].sort_by {|n, _| n}.each do |name, details|
            type, array, required = @support.puppet_type_to_ruby(details["type"])
            description = "%s (%s)" % [details["description"], details["type"]]

            properties = {
              :description => description,
              :arguments => ["--%s %s" % [name.downcase, name.upcase]],
              :type => array ? :array : type,
              :required => required
            }

            properties[:arguments] = ["--%s" % name.downcase] if type == :boolean

            application.class.option(name.intern, properties)
          end
        end

        # Retrieves task metadata from Puppet Server and cache it
        #
        # @param task [String] the task to fetch
        # @param environment [String] Puppet environment
        def task_metadata(task, environment)
          @__metadata ||= {}

          return @__metadata[task] if @__metadata[task]

          @__metadata[task] = @support.task_metadata(task, environment)
        end

        # Draw a compact CLI progress indicator
        #
        # @param msg [String] the message to prefix
        # @param max [Integer] the biggest number to expect
        # @param current [Integer] the current number
        def twirl(msg, max, current)
          charset = ["▖", "▘", "▝", "▗"]
          index = current % charset.size
          char = charset[index]
          char = Util.colorize(:green, "✓") if max == current

          format = "\r%s %s  %#{@max.to_s.size}d / %d"
          format % [msg, char, current, max]
        end
      end
    end
  end
end

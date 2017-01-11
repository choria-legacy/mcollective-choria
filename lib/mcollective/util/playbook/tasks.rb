require_relative "task_result"
require_relative "tasks/base"
require_relative "tasks/mcollective_task"
require_relative "tasks/mcollective_assert_task"
require_relative "tasks/shell_task"
require_relative "tasks/slack_task"
require_relative "tasks/webhook_task"

module MCollective
  module Util
    class Playbook
      class Tasks
        include TemplateUtil

        attr_reader :tasks, :results

        def initialize(playbook)
          @playbook = playbook

          reset
        end

        def reset
          @results = []
          @tasks = {
            "tasks" => [],
            "pre_task" => [],
            "post_task" => [],
            "on_fail" => [],
            "on_success" => [],
            "pre_book" => [],
            "post_book" => []
          }
        end

        def prepare; end

        # @todo support types of runner
        def runner_for(type)
          klass_name = "%sTask" % type.capitalize

          Tasks.const_get(klass_name).new
        rescue NameError
          raise("Cannot find a handler for Task type %s" % type)
        end

        # Runs a specific task
        #
        # @param task [Hash] a task entry
        # @param set [String] the set the task is running in
        # @param hooks [Boolean] indicates if hooks should be run
        # @return [Boolean] indicating task success
        def run_task(task, set, hooks=true)
          properties = task[:properties]
          result = task[:result]
          task_runner = task[:runner]

          Log.info("About to run task: %s" % properties["description"]) if properties["description"]

          if hooks && !run_set("pre_task")
            Log.warn("Failing task because a critical pre_task hook failed")
            return false
          end

          (1..properties["tries"]).each do |try|
            task_runner.from_hash(t(properties))
            task_runner.validate_configuration!

            @results << result.timed_run(task, set)

            Log.info(result.msg)

            if try != properties["tries"] && !result.success
              Log.warn("Task failed on try %d/%d, sleeping %ds: %s" % [try, properties["tries"], properties["try_sleep"], result.msg])
              sleep(properties["try_sleep"])
            end

            break if result.success
          end

          if hooks && !run_set("post_task")
            Log.warn("Failing task because a critical post_task hook failed")
            return false
          end

          result.success
        end

        # Runs a specific task set
        #
        # @param set [String] one of the known task sets
        # @return [Boolean] true if all tasks and all their hooks passed
        def run_set(set)
          set_tasks = @tasks[set]

          return true if set_tasks.empty?

          @playbook.in_context(set) do
            Log.info("About to run task set %s with %d task(s)" % [set, set_tasks.size])

            # would typically use map here but you cant break out of a map and keep the thus far built up array
            # so it's either this or a inject loop
            passed = set_tasks.take_while do |task|
              @playbook.in_context("%s.%s" % [set, task[:type]]) { run_task(task, set, set == "tasks") }
            end

            set_success = passed.size == set_tasks.size

            Log.info("Done running task set %s with %d task(s): success: %s" % [set, set_tasks.size, set_success])

            set_success
          end
        end

        def run
          @playbook.in_context("running") do
            unless run_set("pre_book")
              Log.warn("Playbook pre_book hook failed to run, failing entire playbook")
              return false
            end

            success = run_set("tasks")

            Log.info("Finished running main tasks in playbook: success: %s" % success)

            if success
              success = run_set("on_success")
            else
              run_set("on_fail")
            end

            unless run_set("post_book")
              Log.warn("Playbook post_book hook failed to run, failing entire playbookbook")
              return false
            end

            success
          end
        end

        def load_tasks(data, set)
          data.each_with_index do |task, idx|
            task.each do |type, props|
              Log.debug("Loading task %d of type %s into %s" % [idx, type, set])

              runner = runner_for(type)
              runner.description = props.fetch("description", "%s task" % [type])

              @tasks[set] << {
                :result => TaskResult.new,
                :description => runner.description,
                :type => type,
                :runner => runner,
                :properties => {
                  "tries" => 1,
                  "try_sleep" => 10,
                  "fail_ok" => false
                }.merge(props)
              }
            end
          end
        end

        def from_hash(data)
          if data.is_a?(Array)
            load_tasks(data, "tasks")
          else
            data.each do |set, tasks|
              load_tasks(tasks, set)
            end
          end

          self
        end
      end
    end
  end
end

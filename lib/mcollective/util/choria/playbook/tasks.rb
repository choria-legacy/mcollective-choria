require_relative "tasks/rpc"
require_relative "tasks/helper"

module MCollective
  module Util
    class Choria
      class Playbook
        class Tasks
          attr_reader :tasks, :playbook, :processed, :on_fail

          FAIL_MODES = ["fail", "continue"]

          def initialize(playbook)
            @tasks = []
            @playbook = playbook
            @success = false
            @processed = 0
            @on_fail = "fail"
          end

          def on_fail=(mode)
            raise("Unknown failure mode %s should be 'fail' or 'continue'") unless FAIL_MODES.include?(mode)
            @on_fail = mode
          end

          def size
            @tasks.size
          end

          # @todo validate all the tasks and helpers exist
          # @todo hooks
          # @todo per task on_fail
          def run!
            playbook.info("Starting processing %d tasks" % tasks.size)

            tasks.each_with_index do |task, idx|
              runner = task_runner(task)
              task_success = false

              playbook.info("Starting to process task %d/%d %s" % [idx+1, size, runner.to_s])

              begin
                runner.run!
                task_success = runner.success
              rescue
                task_success = false
              end

              if task_success
                playbook.info("Task %d completed succesfully" % [idx + 1])
              else
                playbook.warn(runner.fail_reason)

                if on_fail == "fail"
                  @success = false
                  raise("Task %s failed to run: %s" % [runner.to_s, runner.fail_reason])
                else
                  playbook.warn("Task runner %s failed: %s" % [runner.to_s, runner.fail_reason])
                  playbook.info("Task runner %s failed but on_fail is set to continue, ignoring" % [runner.to_s])
                end
              end

              @processed += 1
            end

            @success = true
          ensure
            playbook.info("Completed processing %d tasks" % processed)
          end

          def task_runner(task)
            type = task.keys.first
            properties = task[type]

            runner_klass = runner_for(type)

            if runner_klass
              runner = runner_klass.new(playbook)
              runner.from_source(properties)
            else
              raise("Could not find a runner for %s tasks" % type)
            end

            runner
          end

          def runner_for(type)
            self.class.const_get(type.capitalize.intern)
          rescue
            nil
          end

          def from_source(tasks)
            @tasks = tasks
          end
        end
      end
    end
  end
end



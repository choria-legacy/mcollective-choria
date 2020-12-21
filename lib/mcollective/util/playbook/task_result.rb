module MCollective
  module Util
    class Playbook
      class TaskResult
        attr_accessor :success, :msg, :data, :ran, :task, :set, :start_time, :end_time, :description

        def initialize(task)
          @start_time = Time.now
          @end_time = @start_time
          @ran = false
          @task = task
          @description = task[:description]
        end

        def task_type
          @task[:type]
        end

        def run_time
          @end_time - @start_time
        end

        def success?
          !!success
        end

        def timed_run(set)
          @start_time = Time.now
          @set = set

          begin
            @success, @msg, @data = task[:runner].run

            if !@success && task[:properties]["fail_ok"] && task[:properties]["tries"] == 1
              Log.warn("Task failed but fail_ok is true, treating as success")
              @success = true
            end
          rescue
            @success = false
            @data = [$!]
            @msg = "Running task %s failed unexpectedly: %s: %s" % [task.to_s, $!.class, $!.to_s]

            Log.warn(@msg)
            Log.debug($!.backtrace.join("\n\t"))
          end

          @end_time = Time.now
          @ran = true

          self
        end
      end
    end
  end
end

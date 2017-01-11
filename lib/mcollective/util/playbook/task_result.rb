module MCollective
  module Util
    class Playbook
      class TaskResult
        attr_accessor :success, :msg, :data, :ran, :task, :set

        def initialize
          @start_time = Time.now
          @end_time = @start_time
          @ran = false
          @task = nil
          @set = nil
        end

        def run_time
          @end_time - @start_time
        end

        def success?
          !!success
        end

        def timed_run(task, set)
          @start_time = Time.now
          @task = task
          @set = set

          begin
            @success, @msg, @data = task[:runner].run

            if !@success && task[:properties]["fail_ok"]
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

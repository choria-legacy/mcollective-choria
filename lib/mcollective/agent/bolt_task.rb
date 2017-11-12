require "mcollective/util/choria"
require "mcollective/util/tasks_support"

module MCollective
  module Agent
    class Bolt_task < RPC::Agent
      activate_when do
        Util::Choria.new.tasks_support.tasks_compatible?
      end

      action "download" do
        reply[:downloads] = 0

        tasks = support_factory

        reply.fail!("Received empty or invalid task file specification", 3) unless request[:files]

        files = JSON.parse(request[:files])

        if tasks.cached?(files)
          reply[:downloads] = 0
        elsif tasks.download_files(files)
          reply[:downloads] = files.size
        else
          reply.fail!("Could not download task %s files: %s" % [request[:task], $!.to_s], 1)
        end
      end

      action "run_and_wait" do
        tasks = support_factory

        reply[:task_id] = request.uniqid

        task = {
          "task" => request[:task],
          "input_method" => request[:input_method],
          "input" => request[:input],
          "files" => JSON.parse(request[:files])
        }

        reply.fail!("Task %s is not available or does not match the specification" % task["task"], 3) unless tasks.cached?(task["files"])

        status = nil

        # Wait for near the timeout and on timeout give up and fetch the
        # status so users can get good replies that include how things are
        # near timeout
        begin
          Timeout.timeout(timeout - 2) do
            status = tasks.run_task_command(reply[:task_id], task, true, request.caller)
          end
        rescue Timeout::Error
          status = tasks.task_status(reply[:task_id])
        ensure
          reply_task_status(status) if status
        end
      end

      action "run_no_wait" do
        tasks = support_factory

        reply[:task_id] = request.uniqid

        task = {
          "task" => request[:task],
          "input_method" => request[:input_method],
          "input" => request[:input],
          "files" => JSON.parse(request[:files])
        }

        status = tasks.run_task_command(reply[:task_id], task, false, request.caller)

        unless status["wrapper_spawned"]
          reply.fail!("Could not spawn task %s: %s" % [request[:task], status["wrapper_error"]])
        end
      end

      action "task_status" do
        tasks = support_factory

        begin
          status = tasks.task_status(request[:task_id])
        rescue
          reply.fail!($!.to_s, 3)
        end

        reply_task_status(status)

        unless status["wrapper_spawned"]
          reply.fail!("Could not spawn task %s: %s" % [request[:task], status["wrapper_error"]])
        end
      end

      def support_factory
        Util::Choria.new.tasks_support
      end

      # Performs an additional authorization and audit using the task name as action
      def before_processing_hook(msg, connection)
        original_action = request.action
        task = request[:task]

        begin
          if ["run_and_wait", "run_no_wait"].include?(original_action) && task
            request.action = task

            begin
              authorization_hook(request) if respond_to?("authorization_hook")
            rescue
              raise(RPCAborted, "You are not authorized to run Bolt Task %s" % task)
            end

            audit_request(request, connection)
          end
        ensure
          request.action = original_action
        end
      end

      def reply_task_status(status)
        reply[:exitcode] = status["exitcode"]
        reply[:stdout] = status["stdout"]
        reply[:stderr] = status["stderr"]
        reply[:completed] = status["completed"]
        reply[:runtime] = status["runtime"]
        reply[:start_time] = status["start_time"].to_i
        reply[:task] = status["task"]
        reply[:callerid] = status["caller"]

        reply.fail("Task failed", 1) if status["exitcode"] != 0 && status["completed"]
      end
    end
  end
end

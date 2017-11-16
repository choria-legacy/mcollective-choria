require "mcollective/util/choria"
require "mcollective/util/tasks_support"

module MCollective
  module Agent
    class Bolt_task < RPC::Agent
      action "download" do
        reply[:downloads] = 0

        tasks = support_factory

        reply.fail!("Received empty or invalid task file specification", 4) unless request[:files]

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

        unless tasks.tasks_compatible?
          msg = "Cannot execute Bolt tasks as the node is not meed the compatability requirements"
          reply[:stdout] = make_error(msg, "choria/not_compatible", {}).to_json
          reply.fail!(msg, 5)
        end

        reply[:task_id] = request.uniqid

        task = {
          "task" => request[:task],
          "input_method" => request[:input_method],
          "input" => request[:input],
          "files" => JSON.parse(request[:files])
        }

        unless tasks.cached?(task["files"])
          msg = "Task %s is not available or does not match the specification" % task["task"]
          reply[:stdout] = make_error(msg, "choria/invalid_cache", {}).to_json
          reply.fail!(msg, 5)
        end

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

        unless tasks.tasks_compatible?
          msg = "Cannot execute Bolt tasks as the node is not meed the compatability requirements"
          reply[:stdout] = make_error(msg, "choria/not_compatible", {}).to_json
          reply.fail!(msg, 5)
        end

        reply[:task_id] = request.uniqid

        task = {
          "task" => request[:task],
          "input_method" => request[:input_method],
          "input" => request[:input],
          "files" => JSON.parse(request[:files])
        }

        status = tasks.run_task_command(reply[:task_id], task, false, request.caller)

        unless status["wrapper_spawned"]
          msg = "Could not spawn task %s: %s" % [request[:task], status["wrapper_error"]]
          reply[:stdout] = make_error(msg, "choria/wrapper_failed", "error" => status["wrapper_error"]).to_json
          reply.fail!(msg, 5)
        end
      end

      action "task_status" do
        tasks = support_factory

        unless tasks.task_ran?(request[:task_id])
          msg = "Task %s have not been run" % request[:task_id]
          reply[:stdout] = make_error(msg, "choria/unknown_task", "taskid" => request[:task_id]).to_json
          reply.fail!(msg, 3)
        end

        begin
          status = tasks.task_status(request[:task_id])
        rescue
          reply[:stdout] = make_error($!.to_s, "choria/status_failed", "taskid" => request[:task_id]).to_json
          reply.fail!($!.to_s, 5)
        end

        reply_task_status(status)

        if reply.statuscode == 0 && !status["wrapper_spawned"]
          reply.fail!("Could not spawn task %s: %s" % [request[:task], status["wrapper_error"]])
        end
      end

      def make_error(msg, kind, detail)
        {
          "_error" => {
            "msg" => msg,
            "kind" => kind,
            "details" => detail
          }
        }
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
        reply[:stdout] = status["stdout"].to_json
        reply[:stderr] = status["stderr"]
        reply[:completed] = status["completed"]
        reply[:runtime] = status["runtime"]
        reply[:start_time] = status["start_time"].to_i
        reply[:task] = status["task"]
        reply[:callerid] = status["caller"]

        if status["stdout"]["_error"]
          reply.fail("%s: %s" % [status["stdout"]["_error"]["kind"], status["stdout"]["_error"]["msg"]])
        elsif support_factory.task_failed?(status)
          reply.fail("Task failed without any error details", 1)
        end
      end
    end
  end
end

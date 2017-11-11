require "mcollective/util/choria"
require "mcollective/util/tasks_support"

module MCollective
  module Agent
    class Bolt_task < RPC::Agent
      action "download" do
        tasks = Util::Choria.new.tasks_support

        meta = tasks.task_metadata(request[:task], request[:environment])

        reply.fail!("Did not receive valid metadata from Puppet Server for task %s" % request[:task]) if meta.empty?
        reply.fail!("Received different file specification from Puppet than requested") unless meta["files"] == JSON.parse(request[:files])

        if tasks.download_task(meta)
          reply[:downloads] = meta["files"].size
        else
          reply[:downloads] = 0
          reply.fail!("Could not download task %s files: %s" % [request[:task], $!.to_s])
        end
      end

      action "run_and_wait" do
        tasks = Util::Choria.new.tasks_support

        reply[:task_id] = request.uniqid

        task = {
          "task" => request[:task],
          "input_method" => request[:input_method],
          "input" => request[:input],
          "files" => JSON.parse(request[:files])
        }

        status = nil

        # Wait for near the timeout and on timeout give up and fetch the
        # status so users can get good replies that include how things are
        # near timeout
        begin
          Timeout.timeout(timeout - 2) do
            status = tasks.run_task_command(reply[:task_id], task)
          end
        rescue Timeout::Error
          status = tasks.task_status(reply[:task_id])
        ensure
          reply_task_status(status) if status
        end
      end

      action "run_no_wait" do
        tasks = Util::Choria.new.tasks_support

        reply[:task_id] = request.uniqid

        task = {
          "task" => request[:task],
          "input_method" => request[:input_method],
          "input" => request[:input],
          "files" => JSON.parse(request[:files])
        }

        tasks.run_task_command(reply[:task_id], task)
      end

      action "task_status" do
        tasks = Util::Choria.new.tasks_support

        reply_task_status(tasks.task_status(request[:task_id]))
      end

      def reply_task_status(status)
        reply[:exitcode] = status["exitcode"]
        reply[:stdout] = status["stdout"]
        reply[:stderr] = status["stderr"]
        reply[:completed] = status["completed"]
        reply[:runtime] = status["runtime"]
        reply[:start_time] = status["start_time"]
      end
    end
  end
end

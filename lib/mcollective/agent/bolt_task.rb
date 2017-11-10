require "mcollective/util/choria"
require "mcollective/util/tasks_support"

module MCollective
  module Agent
    class Bolt_task < RPC::Agent
      action "download" do
        tasks = Util::Choria.new.tasks_support

        meta = tasks.task_metadata(request[:task], request[:environment])

        reply.fail!("Did not receive valid metadata from Puppet Server for task %s" % request[:task]) if meta.empty?

        if request[:files] && !request[:files] == "[]"
          reply.fail!("Received different file specification from Puppet than requested") unless meta["files"] == JSON.parse(request[:files])
        else
          Log.warn("Downloading bolt task %s without a file specification" % [request[:task]])
        end

        if tasks.download_task(meta)
          reply[:downloads] = meta["files"].size
        else
          reply[:downloads] = 0
          reply.fail!("Could not download task %s files: %s" % [request[:task], $!.to_s])
        end
      end
    end
  end
end

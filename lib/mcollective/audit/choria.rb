module MCollective
  module Audit
    class Choria < RPC::Audit
      def audit_request(request, connection)
        logfile = Config.instance.pluginconf["rpcaudit.logfile"]

        unless logfile
          Log.warn("Auditing is not functional because rpcaudit.logfile is not set")
          return
        end

        unless File.writable?(logfile)
          Log.warn("Auditing is not functional because logfile '%s' is not writable" % logfile)
          return
        end

        message = {
          "timestamp" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
          "request_id" => request.uniqid,
          "request_time" => request.time,
          "caller" => request.caller,
          "sender" => request.sender,
          "agent" => request.agent,
          "action" => request.action,
          "data" => request.data
        }

        File.open(logfile, "a") do |f|
          f.puts(message.to_json)
        end
      end
    end
  end
end

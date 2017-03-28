module MCollective
  module Audit
    class Choria < RPC::Audit
      def audit_request(request, connection)
        logfile = Config.instance.pluginconf["rpcaudit.logfile"]

        unless logfile
          Log.warn("Auditing is not functional because rpcaudit.logfile is not set")
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

        begin
          File.open(logfile, "a") do |f|
            f.puts(message.to_json)
          end
        rescue
          Log.warn("Auditing is not functional because writing to logfile '%s' failed %s: %s" % [logfile, $!.class, $!.to_s])
        end
      end
    end
  end
end

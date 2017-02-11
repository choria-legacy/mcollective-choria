require "tempfile"
require "fileutils"
require "thread"

module MCollective
  module Registration
    class Choria < Base
      attr_writer :connection

      def run(connection)
        return false if interval == 0

        @connection = connection

        Thread.new do
          publish_thread
        end
      end

      def publish_thread
        loop do
          begin
            publish
          rescue Exception # rubocop:disable Lint/RescueException
            Log.error("Could not write Choria stats data to %s: %s: %s" % [registration_file, $!.class, $!.to_s])
          ensure
            sleep(interval)
          end
        end
      end

      def publish
        tempfile = Tempfile.new(File.basename(registration_file), File.dirname(registration_file))
        tempfile.write(registration_data.to_json)
        tempfile.close

        File.chmod(0o0644, tempfile.path)
        File.rename(tempfile.path, registration_file)
      end

      def connected_server
        if @connection.connected?
          @connection.connected_server
        else
          "disconnected"
        end
      end

      def connector_stats
        @connection.stats
      end

      def interval
        config.registerinterval
      end

      def registration_file
        if config.pluginconf["choria.registration.file"]
          config.pluginconf["choria.registration.file"]
        else
          File.join(File.dirname(config.logfile), "choria-stats.json")
        end
      end

      def registration_data
        {
          "timestamp" => Time.now.to_i,
          "identity" => config.identity,
          "version" => MCollective::VERSION,
          "stats" => PluginManager["global_stats"].to_hash,
          "nats" => {
            "connected_server" => connected_server,
            "stats" => connector_stats
          }
        }
      end

      def config
        Config.instance
      end
    end
  end
end

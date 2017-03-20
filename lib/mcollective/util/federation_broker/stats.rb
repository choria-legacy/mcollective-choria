require "webrick/httpserver"

module MCollective
  module Util
    class FederationBroker
      class Stats
        # @param broker [FederationBroker]
        def initialize(broker)
          @broker = broker
          @lock = Mutex.new
          @stats = initial_stats

          start_stats_web_server if stats_port
          start_stats_publisher
        end

        # Initial empty stats
        #
        # @return [Hash]
        def initial_stats
          {
            "version" => Choria::VERSION,
            "start_time" => Time.now.to_i,
            "cluster" => @broker.cluster_name,
            "instance" => @broker.instance_name,
            "config_file" => Config.instance.configfile,
            "status" => "unknown",
            "threads" => {},
            "collective" => {},
            "federation" => {},
            "/stats" => {
              "requests" => 0
            }
          }
        end

        # The port used to listen on for HTTP stats requests
        #
        # @return [Integer,nil]
        def stats_port
          @broker.stats_port
        end

        # Updates the stats hash with current information from the broker
        #
        # @return [Hash] the updated stats
        def update_broker_stats
          @lock.synchronize do
            @stats["threads"] = @broker.thread_status
            @stats["status"] = @broker.ok? ? "OK" : "CRITICAL"
            @stats["collective"] = @broker.processors["collective"].stats
            @stats["federation"] = @broker.processors["federation"].stats

            @stats
          end
        end

        # Services a request for stats
        #
        # @param req [WEBrick::HTTPRequest]
        # @param res [WEBrick::HTTPResponse]
        # @return [void]
        def serve_stats(req, res)
          Log.info("/stats request from %s:%d" % [req.peeraddr[2], req.peeraddr[1]])

          @lock.synchronize { @stats["/stats"]["requests"] += 1 }

          res["Content-Type"] = "application/json"
          res.body = JSON.pretty_generate(update_broker_stats)
        end

        def stats_target
          "choria.federation.%s.stats" % [@broker.cluster_name]
        end

        # Starts a thread that publishes the broker stats every 10 seconds
        def start_stats_publisher
          Log.info("Starting statistics publisher publishing to %s" % stats_target)

          thread = Thread.new do
            begin
              loop do
                sleep 10

                next unless @broker.started?

                @broker.connections["federation"].publish(stats_target, update_broker_stats.to_json)
              end
            rescue
              Log.error("Failed to publish stats to federation %s: %s: %s" % [stats_target, $!.class, $!.to_s])
              Log.debug($!.backtrace.join("\n\t"))

              retry
            end
          end

          @broker.record_thread("stats_publisher", thread)
        end

        # Starts a Webrick server serving stats requests
        #
        # @note when there is no stats_port configured this will do nothing
        # @return [void]
        def start_stats_web_server
          return unless stats_port

          thread = Thread.new do
            begin
              Log.info("Listening for stats requests on localhost:%d/stats" % [stats_port])

              server = WEBrick::HTTPServer.new(
                :Port => stats_port,
                :BindAddress => "127.0.0.1",
                :Logger => Log,
                :ServerSoftware => "Choria Federation Broker %s" % [Choria::VERSION],
                :AccessLog => []
              )

              server.mount_proc("/stats") {|req, res| serve_stats(req, res) }

              server.start unless ENV["CHORIA_RAKE"]
            rescue
              Log.error("Could not start stats server: %s: %s" % [$!.class, $!.to_s])
              Log.debug($!.backtrace.join("\n\t"))
              sleep 1

              retry
            end
          end

          @broker.record_thread("stats_web_server", thread)
        end
      end
    end
  end
end

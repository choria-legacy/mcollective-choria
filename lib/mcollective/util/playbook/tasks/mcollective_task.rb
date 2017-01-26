module MCollective
  module Util
    class Playbook
      class Tasks
        class McollectiveTask < Base
          def startup_hook
            @properties = {}
            @post = []
            @nodes = []
          end

          # Creates and cache an RPC::Client for the configured agent
          #
          # @param from_cache [Boolean] when false a new instance is always returned
          # @return [RPC::Client]
          def client(from_cache=true)
            if from_cache
              @_rpc_client ||= create_and_configure_client
            else
              create_and_configure_client
            end
          end

          # Creates a new RPC::Client and configures it with the configured settings
          #
          # @todo discovery
          # @return [RPC::Client]
          def create_and_configure_client
            client = RPC::Client.new(@agent, :configfile => Util.config_file_for_user)
            client.batch_size = @batch_size if @batch_size
            client.discover(:nodes => @nodes)
            client.progress = false
            client
          end

          # Validates the internal configuration of the task
          #
          # @raise [StandardError] on failure of the internal state
          def validate_configuration!
            raise("Nodes need to be supplied, refusing to run against empty node list") if @nodes.empty?
          end

          # Parse an action in the form agent.action
          #
          # @todo check it complies to format
          # @param action [String] in the form agent.action
          # @return [Array<String, String>] the agent and action parts
          def parse_action(action)
            action.split(".")
          end

          # Initialize the task from a hash
          #
          # @param data [Hash] input data matching tasks/rpc.json schema
          # @return [McollectiveTask]
          def from_hash(data)
            @nodes = data.fetch("nodes", [])
            @agent, @action = parse_action(data["action"])
            @batch_size = data["batch_size"]
            @properties = data.fetch("properties", {})
            @post = data.fetch("post", [])
            @log_replies = !data.fetch("silent", false)

            @_rpc_client = nil

            self
          end

          # Determines the run result
          #
          # @param stats [RPC::Stats]
          # @param replies [Array<RPC::Result>]
          # @return [Array<Boolean, String, Array<Hash>>] success, message, rpc replies
          def run_result(stats, replies)
            reply_data = replies.map do |reply|
              {
                "agent" => reply.agent,
                "action" => reply.action,
                "sender" => reply.results[:sender],
                "statuscode" => reply.results[:statuscode],
                "statusmsg" => reply.results[:statusmsg],
                "data" => reply.results[:data],
                "requestid" => stats.requestid
              }
            end

            if request_success?(stats)
              [true, "Successful request %s for %s#%s on %d node(s)" % [stats.requestid, @agent, @action, stats.okcount], reply_data]
            else
              failed = stats.failcount + stats.noresponsefrom.size
              [false, "Failed request %s for %s#%s on %d failed node(s)" % [stats.requestid, @agent, @action, failed], reply_data]
            end
          end

          # Logs the result of a request
          #
          # @param stats [RPC::Stats]
          # @param replies [Array<RPC::Result>]
          def log_results(stats, replies)
            if request_success?(stats)
              log_success(stats)
            else
              log_failure(stats, replies)
            end
          end

          # Logs a successfull request
          #
          # @param stats [RPC::Stats]
          def log_success(stats)
            Log.debug("Successful request %s for %s#%s in %0.2fs against %d node(s)" % [stats.requestid, @agent, @action, stats.totaltime, stats.okcount])
          end

          def log_summarize(stats)
            summary = {}

            if stats.aggregate_summary.size + stats.aggregate_failures.size > 0
              stats.aggregate_summary.each do |aggregate|
                summary.merge!(aggregate.result[:value])
              end
            end

            unless summary.empty?
              if @description
                desc = "%s (%s#%s)" % [@description, @agent, @action]
              else
                desc = "%s#%s" % [@agent, @action]
              end

              Log.info("Summary for %s: %s" % [desc, summary.inspect])
            end
          end

          # Logs a failed request
          #
          # @param stats [RPC::Stats]
          # @param replies [Array<RPC::Result>]
          def log_failure(stats, replies)
            stats = client.stats

            Log.warn("Failed request %s for %s#%s in %0.2fs. %d successful node(s)" % [stats.requestid, @agent, @action, stats.totaltime, stats.okcount])

            unless stats.noresponsefrom.empty?
              Log.warn("No responses from: %s" % stats.noresponsefrom.join(", "))
            end

            if stats.failcount > 0
              replies.each do |reply|
                if reply.results[:statuscode] > 0
                  Log.warn("Failed result from %s: %s" % [reply.results[:sender], reply.results[:statusmsg]])
                end
              end
            end
          end

          def log_reply(reply)
            if reply.results[:statuscode] == 0
              return unless @log_replies
              Log.info("%s %s#%s success: %s" % [reply.results[:sender], @agent, @action, reply.results[:data].inspect])
            else
              Log.warn("%s %s#%s failure: %s" % [reply.results[:sender], @agent, @action, reply.results[:data].inspect])
            end
          end

          # Determines if a request was succesfull
          #
          # @param stats [RPC::Stats]
          # @return [Boolean]
          def request_success?(stats)
            return false if stats.failcount > 0
            return false if stats.okcount == 0
            return false unless stats.noresponsefrom.empty?
            true
          end

          # Logs a single RPC reply
          # Performs a single attempt at calling the agent
          # @todo should return some kind of task status object
          # @return [Array<Boolean, String, Array<RPC::Result>>] success, message, rpc replies
          def run
            Log.info("Starting request for %s#%s against %d nodes" % [@agent, @action, @nodes.size])

            begin
              replies = []

              client.send(@action, @properties) do |_, s|
                replies << s
                log_reply(s)
              end

              log_summarize(client.stats) if @post.include?("summarize")
              log_results(client.stats, replies)
              run_result(client.stats, replies)
            rescue
              msg = "Could not create request for %s#%s: %s: %s" % [@agent, @action, $!.class, $!.to_s]
              Log.debug(msg)
              Log.debug($!.backtrace.join("\t\n"))

              [false, msg, []]
            end
          end
        end
      end
    end
  end
end

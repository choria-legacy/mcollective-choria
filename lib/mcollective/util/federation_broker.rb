require_relative "choria"
require_relative "natswrapper"
require_relative "federation_broker/stats"
require_relative "federation_broker/base"
require_relative "federation_broker/collective_processor"
require_relative "federation_broker/federation_processor"

module MCollective
  module Util
    class FederationBroker
      attr_reader :cluster_name, :instance_name, :stats, :processors, :connections

      # @private
      attr_reader :threads, :choria

      # @param cluster_name [String] the name of the federation broker cluster
      # @param instance_name [String, nil] the name of this specific instance in the cluster
      # @param stats_port [Integer] the port to listen to for stats, uses choria.stats_port when nil
      def initialize(cluster_name, instance_name=nil, stats_port=nil)
        @started = false

        @processors_lock = Mutex.new
        @threads_lock = Mutex.new

        @threads = {}
        @processors = {}
        @connections = {}

        @cluster_name = cluster_name
        @instance_name = instance_name || SSL.uuid

        @stats_port = stats_port
        @choria = Choria.new(nil, nil, false)
        @config = Config.instance
        @stats = Stats.new(self)

        @to_federation = Queue.new
        @to_collective = Queue.new
      end

      # The port used to listen on for HTTP stats requests
      #
      # @see Choria#start_port
      # @return [Integer,nil]
      def stats_port
        @stats_port || @choria.stats_port
      end

      # Stores a thread in the global thread list
      #
      # Threads stored here will be checked via {#ok?}
      # and reports in stats via {#thread_status}
      #
      # @param name [String]
      # @param thread [Thread]
      # @raise [StandardError] when a thread by that name exist already
      def record_thread(name, thread)
        @threads_lock.synchronize do
          raise("Thread called '%s' already exist in the thread registry" % name) if @threads.include?(name)
          @threads[name] = thread
          @threads[name]["_name"] = name
        end
      end

      # Determines if the Broker has been started
      #
      # @return [Boolean]
      def started?
        @started
      end

      # Determines if all the threads are alive
      #
      # @todo just a alive? check isnt enough, workers should have some introspection
      # @return [Boolean]
      def ok?
        @threads_lock.synchronize { @threads.all? {|_, thr| thr.alive?} }
      end

      # Status for all component threads
      #
      # @return [Hash] of `alive` and `status` for every thread
      def thread_status
        @threads_lock.synchronize do
          Hash[@threads.map do |name, thread|
            [name, "alive" => thread.alive?, "status" => thread.status]
          end]
        end
      end

      # Connect to the federation and observes published stats
      #
      # This will yield a hash of stats for every instance in the
      # Federation Broker in {@cluster_name}
      def observe_stats
        ENV["CHORIA_FED_COLLECTIVE"] = @cluster_name

        servers = Choria.new(nil, nil, false).middleware_servers("puppet", "4222").map do |host, port|
          URI("nats://%s:%s" % [host, port])
        end.map(&:to_s)

        lock = Mutex.new

        cluster_stats = {}

        federation = FederationProcessor.new(self)
        federation.start_connection(servers)

        Thread.new do
          federation.consume_from(:name => stats.stats_target) do |msg|
            stats = JSON.parse(msg)

            if stats["cluster"] == @cluster_name
              lock.synchronize { cluster_stats[stats["instance"]] = stats }
            end
          end
        end

        loop do
          lock.synchronize { yield(cluster_stats) }
          sleep 1
        end
      end

      # Starts the broker
      #
      # @note this method is non blocking, the federation continues to run in the background in threads
      def start
        @processors["collective"] = CollectiveProcessor.new(self, @to_collective, @to_federation)
        @processors["federation"] = FederationProcessor.new(self, @to_federation, @to_collective)

        @connections["collective"] = @processors["collective"].start
        @connections["federation"] = @processors["federation"].start

        @started = true
      end
    end
  end
end

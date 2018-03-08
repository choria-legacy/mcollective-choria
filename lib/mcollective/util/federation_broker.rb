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
        @choria = Choria.new(false)
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

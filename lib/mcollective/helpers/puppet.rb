module MCollective
  class Helpers
    class Puppet
      attr_reader :logger, :nodes

      def initialize(logger)
        @logger = logger
      end

      def nodes=(nodes)
        @nodes = nodes
        puppet.discover(:nodes => nodes)
      end

      def stats
        puppet.stats
      end

      def all_responded?
        stats.noresponsefrom.empty?
      end

      def all_passed?
        stats.failcount == 0
      end

      def ok?
        all_responded? && all_passed?
      end

      def puppet
        return @puppet if @puppet

        options = {:verbose      => false,
                   :config       => Util.config_file_for_user,
                   :progress_bar => false,
                   :filter       => Util.empty_filter}

        @puppet = MCollective::RPC::Client.new("puppet", :configfile => options[:config], :options => options)

        @puppet
      end

      def wait_till_idle(options)
        options = {"checks" => 60, "sleep" => 10}.merge(options)

        puppet.discover(:nodes => @nodes) if @nodes

        options["checks"].times do |i|
          logger.debug("Waiting for %d nodes to become idle" % [puppet.discover.size])

          puppet.status

          return if ok?

          logger.info("Still waiting for %d nodes to become idle after %d/%d tries, sleeping %d seconds" % [i+1, options["checks"], options["sleep"]])

          sleep(options["sleep"])
        end

        raise("Timeout while waiting for %d nodes to idle after %d tries" % [puppet.discover.size, options["checks"]])
      end
    end
  end
end



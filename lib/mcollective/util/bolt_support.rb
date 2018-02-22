require "mcollective"
require_relative "choria"
require_relative "playbook"

require_relative "bolt_support/task_result"
require_relative "bolt_support/task_results"
require_relative "bolt_support/plan_runner"

module MCollective
  module Util
    class BoltSupport
      def choria
        @__choria ||= Choria.new
      end

      # Converts the current Puppet loglevel to one we understand
      #
      # @return ["debug", "info", "warn", "error", "fatal"]
      def self.loglevel
        case Puppet::Util::Log.level
        when :notice
          "warn"
        when :warning
          "warn"
        when :err
          "error"
        when :alert, :emerg, :crit
          "fatal"
        else
          Puppet::Util::Log.level.to_s
        end
      end

      # Configures MCollective and initialize the Bolt Support class
      #
      # @return [BoltSupport]
      def self.init_choria
        unless Config.instance.configured
          Config.instance.loadconfig(Util.config_file_for_user)
        end

        new
      end

      # Creates a configured instance of the Playbook
      #
      # @return [Playbook]
      def playbook
        @_playbook ||= begin
                         pb = Playbook.new(self.class.loglevel)
                         pb.logger = Playbook::Puppet_Logger
                         pb.set_logger_level
                         pb
                       end
      end

      def nodes
        @_nodes ||= Playbook::Nodes.new(playbook)
      end

      # Discovers nodes using playbook node sets
      #
      # @param scope [Puppet::Parser::Scope] scope to log against
      # @param type [String] a known node set type like `terraform`
      # @param properties [Hash] properties valid for the node set type
      def discover_nodes(scope, type, properties)
        uses_properties = properties.delete("uses") || {}
        playbook.logger.scope = scope
        playbook.uses.from_hash(uses_properties)

        nodes.from_hash("task_nodes" => properties.merge(
          "type" => type,
          "uses" => uses_properties.keys
        ))

        nodes.prepare
        nodes["task_nodes"]
      end

      # Retrieves a data item from a data store
      #
      # @param scope [Puppet::Parser::Scope] scope to log against
      # @param item [String] the item to fetch
      # @param properties [Hash] the data source properties
      def data_read(scope, item, properties)
        playbook.logger.scope = scope
        playbook.data_stores.from_hash("plan_store" => properties)
        playbook.data_stores.prepare
        playbook.data_stores.read("plan_store/%s" % item)
      end

      # Writes a value to a data store
      #
      # @param scope [Puppet::Parser::Scope] scope to log against
      # @param item [String] the item to fetch
      # @param value [String] the item to fetch
      # @param properties [Hash] the data source properties
      # @return [String] the data that was written
      def data_write(scope, item, value, properties)
        config = {"plan_store" => properties}

        playbook.logger.scope = scope
        playbook.data_stores.from_hash(config)
        playbook.data_stores.prepare
        playbook.data_stores.write("plan_store/%s" % item, value)
      end

      # Performs a block within a lock in a data store
      #
      # @param scope [Puppet::Parser::Scope] scope to log against
      # @param item [String] the lock key
      # @param properties [Hash] the data source properties
      def data_lock(scope, item, properties, &blk)
        locked = false
        lock_path = "plan_store/%s" % item
        config = {"plan_store" => properties}

        playbook.logger.scope = scope
        playbook.data_stores.from_hash(config)
        playbook.data_stores.prepare

        playbook.data_stores.lock(lock_path)
        locked = true

        yield
      ensure
        playbook.data_stores.release(lock_path) if locked
      end

      # Runs a playbook task and return execution results
      #
      # @param scope [Puppet::Parser::Scope] scope to log against
      # @param type [String] the task type
      # @param properties [Hash] properties passed to the task
      # @return [Hash] formatted for BoltSupport::TaskResults
      def run_task(scope, type, properties)
        task_properties = properties.reject {|k, _| k.start_with?("_") }
        playbook.logger.scope = scope

        tasks = playbook.tasks.load_tasks([type => task_properties], "tasks")

        playbook.tasks.run_task(tasks[0], "plan", false)

        result = tasks[0][:result]
        runner = tasks[0][:runner]

        execution_result = runner.to_execution_result([result.success, result.msg, result.data])

        return execution_result if result.success
        return execution_result if properties.fetch("fail_ok", false)
        return execution_result if properties["_catch_errors"]

        raise(result.msg)
      end
    end
  end
end

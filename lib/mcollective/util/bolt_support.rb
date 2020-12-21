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
        @_choria ||= Choria.new
      end

      # Converts the current Puppet loglevel to one we understand
      #
      # @return ["debug", "info", "warn", "error", "fatal"]
      def self.loglevel
        case Puppet::Util::Log.level
        when :notice, :warning
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
        Config.instance.loadconfig(Util.config_file_for_user) unless Config.instance.configured

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
        assign_playbook_name(scope)
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
        assign_playbook_name(scope)
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
        assign_playbook_name(scope)
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
        assign_playbook_name(scope)
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
      # @return [BoltSupport::TaskResults]
      def run_task(scope, type, properties)
        task_properties = properties.reject {|k, _| k.start_with?("_") }
        playbook.logger.scope = scope
        assign_playbook_name(scope)

        tasks = playbook.tasks.load_tasks([type => task_properties], "tasks")

        playbook.tasks.run_task(tasks[0], "plan", false)

        result = tasks[0][:result]
        runner = tasks[0][:runner]

        execution_result = runner.to_execution_result([result.success, result.msg, result.data])

        results = execution_result.map do |node, result_properties|
          TaskResult.new(node, JSON.parse(result_properties.to_json))
        end

        task_results = TaskResults.new(results, nil)
        task_results.message = result.msg

        return task_results if result.success
        return task_results if properties.fetch("fail_ok", false)
        return task_results if properties["_catch_errors"]

        raise(result.msg)
      end

      # Assigns the playbook name based on the fact choria.plan
      #
      # @see PlanRunner#in_environment
      def assign_playbook_name(scope)
        return unless scope
        return unless scope["facts"]["choria"]
        return unless scope["facts"]["choria"]["playbook"]

        playbook.metadata["name"] = scope["facts"]["choria"]["playbook"]
      end
    end
  end
end

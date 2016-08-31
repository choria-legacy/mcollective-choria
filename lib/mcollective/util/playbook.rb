require_relative "playbook/playbook_logger"
require_relative "playbook/template_util"
require_relative "playbook/inputs"
require_relative "playbook/uses"
require_relative "playbook/nodes"
require_relative "playbook/tasks"

require "semantic_puppet"

module MCollective
  module Util
    class Playbook
      include TemplateUtil

      attr_accessor :input_data, :context
      attr_reader :loglevel, :metadata

      def initialize(loglevel=nil)
        @loglevel = loglevel

        # @todo dear god this Camel_Snake horror but mcollective requires this
        # Configures the main MCollective logger with our custom logger
        @logger = Log.set_logger(Playbook_Logger.new(self))

        @nodes = Nodes.new(self)
        @tasks = Tasks.new(self)
        @uses = Uses.new(self)
        @inputs = Inputs.new(self)
        @playbook = self
        @playbook_data = {}
        @input_data = {}

        @metadata = {
          "name" => nil,
          "version" => nil,
          "author" => nil,
          "description" => nil,
          "tags" => [],
          "on_fail" => "fail",
          "loglevel" => "info",
          "run_as" => "choria=deployer"
        }
      end

      # Loads the playbook data and prepare the runner
      #
      # @param data [Hash] playbook data
      # @return [Playbook]
      def from_hash(data)
        in_context("loading") do
          @playbook_data = data

          @metadata = {
            "name" => data["name"],
            "version" => data["version"],
            "author" => data["author"],
            "description" => data["description"],
            "tags" => data.fetch("tags", []),
            "on_fail" => data.fetch("on_fail", "fail"),
            "loglevel" => data.fetch("loglevel", "info"),
            "run_as" => data["run_as"]
          }
        end

        set_logger_level

        in_context("inputs") do
          @inputs.from_hash(data.fetch("inputs", {}))
        end

        self
      end

      def prepare
        # do this first for templating down below
        prepare_inputs

        prepare_uses
        prepare_nodes
        prepare_tasks
      end

      # Runs the playbook
      #
      # @param inputs [Hash] input data
      # @param verbose [Boolean] to log verbosely
      # @return [Boolean]
      def run!(inputs)
        start_time = Time.now
        @input_data = inputs

        in_context("pre") { Log.info("Starting playbook %s at %s" % [name, start_time]) }

        prepare

        success = in_context("run") { @tasks.run }
        in_context("post") { Log.info("Done running playbook %s in %s" % [name, seconds_to_human(Integer(Time.now - start_time))]) }

        success
      rescue
        Log.error("Playbook %s failed: %s: %s" % [name, $!.class, $!.to_s])
        Log.debug($!.backtrace.join("\n\t"))

        false
      end

      # Playbook name as declared in metadata
      #
      # @return [String]
      def name
        metadata_item("name")
      end

      # Playbook version as declared in metadata
      #
      # @return [String]
      def version
        metadata_item("version")
      end

      def loglevel
        @loglevel || metadata_item("loglevel") || "info"
      end

      def set_logger_level
        @logger.set_level(loglevel.intern)
      end

      # Prepares the inputs from the playbook
      #
      # @todo same pattern as prepare_uses and nodes
      # @see Inputs#prepare
      # @note this should be done first, before any uses, nodes or tasks are prepared
      def prepare_inputs
        in_context("prep.inputs") { @inputs.prepare(@input_data) }
      end

      # Prepares the uses clauses from the playbook
      #
      # @see Uses#prepare
      def prepare_uses
        in_context("prep.uses") { @uses.from_hash(t(@playbook_data.fetch("uses", {}))).prepare }
      end

      # Prepares the node lists from the Playbook
      #
      # @see Nodes#prepare
      def prepare_nodes
        in_context("prep.nodes") { @nodes.from_hash(t(@playbook_data.fetch("nodes", {}))).prepare }
      end

      # Prepares the tasks lists `tasks` and `hooks` from the Playbook data
      #
      # @see Tasks#prepare
      def prepare_tasks
        # we lazy template parse these so that they might refer to run time
        # state via the template system - like for example in a post task you
        # might want to reference properties of another rpc request
        in_context("prep.tasks") do
          @tasks.from_hash(@playbook_data.fetch("tasks", []))
          @tasks.from_hash(@playbook_data.fetch("hooks", {}))
          @tasks.prepare
        end
      end

      # Validates agent versions on nodes
      #
      # @param agents [Hash] a hash of agent names and nodes that uses that agent
      # @raise [StandardError] on failure
      def validate_agents(agents)
        @uses.validate_agents(agents)
      end

      # Retrieves an item from the metadata
      #
      # @param item [name, version, author, description, tags, on_fail, loglevel, run_as]
      # @return [Object] the corresponding item from `@metadata`
      # @raise [StandardError] for invalid metadata items
      def metadata_item(item)
        if @metadata.include?(item)
          @metadata[item]
        else
          raise("Unknown playbook metadata %s" % item)
        end
      end

      # (see Nodes#[])
      def discovered_nodes(nodeset)
        @nodes[nodeset]
      end

      # (see Inputs#[])
      def input_value(input)
        @inputs[input]
      end

      # Adds the CLI options for an application based on the playbook inputs
      #
      # @see Inputs#add_cli_options
      # @param application [MCollective::Application]
      # @param set_required [Boolean]
      def add_cli_options(application, set_required=false)
        @inputs.add_cli_options(application, set_required)
      end

      def in_context(context)
        old_context = @context
        @context = context

        yield
      ensure
        @context = old_context
      end

      def seconds_to_human(seconds)
        days = seconds / 86400
        seconds -= 86400 * days

        hours = seconds / 3600
        seconds -= 3600 * hours

        minutes = seconds / 60
        seconds -= 60 * minutes

        if days > 1
          "%d days %d hours %d minutes %02d seconds" % [days, hours, minutes, seconds]
        elsif days == 1
          "%d day %d hours %d minutes %02d seconds" % [days, hours, minutes, seconds]
        elsif hours > 0
          "%d hours %d minutes %02d seconds" % [hours, minutes, seconds]
        elsif minutes > 0
          "%d minutes %02d seconds" % [minutes, seconds]
        else
          "%02d seconds" % seconds
        end
      end
    end
  end
end

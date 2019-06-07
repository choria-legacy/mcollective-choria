require_relative "nodes/mcollective_nodes"
require_relative "nodes/pql_nodes"
require_relative "nodes/yaml_nodes"
require_relative "nodes/shell_nodes"
require_relative "nodes/terraform_nodes"

module MCollective
  module Util
    class Playbook
      class Nodes
        attr_reader :nodes

        def initialize(playbook)
          @playbook = playbook
          @nodes = {}
        end

        # List of known node set names
        #
        # @return [Array<String>]
        def keys
          @nodes.keys
        end

        # Nodes belonging to a specific node set
        #
        # @param nodeset [String] node set name
        # @return [Array<String>]
        # @raise [StandardError] when node set is unknown
        def [](nodeset)
          if include?(nodeset)
            @nodes[nodeset][:discovered]
          else
            raise("Unknown node set %s" % nodeset)
          end
        end

        # Properties for a certain node set
        #
        # @param nodes [String] node set name
        # @return [Hash]
        # @raise [StandardError] when node set is unknown
        def properties(nodes)
          if include?(nodes)
            @nodes[nodes][:properties]
          else
            raise("Unknown node set %s" % nodes)
          end
        end

        # Determines if a node set is known
        #
        # @param nodes [String] node set name
        # @return [Boolean]
        def include?(nodes)
          @nodes.include?(nodes)
        end

        def prepare
          @nodes.each do |node_set, dets|
            @playbook.in_context(node_set) do
              Log.debug("Preparing nodeset %s" % node_set)

              resolve_nodes(node_set)
              check_empty(node_set)
              limit_nodes(node_set)
              validate_nodes(node_set)

              Log.info("Discovered %d node(s) in node set %s" % [dets[:discovered].size, node_set])
            end
          end

          @playbook.in_context("conn.test") { test_nodes }
          @playbook.in_context("ddl.test") { check_uses }
        end

        # Resolve the node list using the resolver class
        #
        # @param node_set [String] node set name
        def resolve_nodes(node_set)
          node_props = @nodes[node_set]
          node_props[:resolver].prepare
          node_props[:discovered] = node_props[:resolver].discover.uniq
        end

        # Checks if the agents on the nodes matches the desired versions
        #
        # @raise [StandardError] on error
        def check_uses
          agent_nodes = {}

          @nodes.map do |_, dets|
            dets[:properties].fetch("uses", []).each do |agent|
              agent_nodes[agent] ||= []
              agent_nodes[agent].concat(dets[:discovered])
            end
          end

          @playbook.validate_agents(agent_nodes) unless agent_nodes.empty?
        end

        # Determines if a nodeset needs connectivity test
        #
        # @param nodes [String] node set name
        # @return [Boolean]
        # @raise [StandardError] for unknown node sets
        def should_test?(nodes)
          !!properties(nodes)["test"]
        end

        def mcollective_task
          Tasks::McollectiveTask.new(@playbook)
        end

        # Tests a RPC ping to the discovered nodes
        #
        # @todo is this really needed?
        # @raise [StandardError] on error
        def test_nodes
          nodes_to_test = @nodes.map do |nodes, _|
            self[nodes] if should_test?(nodes)
          end.flatten.compact

          return if nodes_to_test.empty?

          Log.info("Checking connectivity for %d nodes" % nodes_to_test.size)

          rpc = mcollective_task
          rpc.from_hash(
            "nodes" => nodes_to_test,
            "action" => "rpcutil.ping",
            "silent" => true
          )
          success, msg, _ = rpc.run

          unless success
            raise("Connectivity test failed for some nodes: %s" % [msg])
          end
        end

        # Checks that discovered nodes matches stated expectations
        #
        # @param nodes [String] node set name
        # @raise [StandardError] on error
        def validate_nodes(nodes)
          return if properties(nodes)["empty_ok"]

          unless self[nodes].size >= properties(nodes)["at_least"]
            raise("Node set %s needs at least %d nodes, got %d" % [nodes, properties(nodes)["at_least"], self[nodes].size])
          end
        end

        # Handles an empty discovered list
        #
        # @param nodes [String] node set name
        # @raise [StandardError] when empty
        def check_empty(nodes)
          if self[nodes].empty? && !properties(nodes)["empty_ok"]
            raise(properties(nodes)["when_empty"] || "Did not discover any nodes for nodeset %s" % nodes)
          end
        end

        # Limits the discovered list for a node set based on the playbook limits
        #
        # @todo more intelegent limiting with weighted randoms like mco rpc client
        # @param nodes [String] node set name
        def limit_nodes(nodes)
          return if self[nodes].empty?

          if limit = properties(nodes)["limit"]
            Log.debug("Limiting node set %s to %d nodes from %d" % [nodes, limit, @nodes[nodes][:discovered].size])
            @nodes[nodes][:discovered] = @nodes[nodes][:discovered][0..(limit - 1)]
          end
        end

        # Retrieves a new instance of the resolver for a certain type of discovery
        #
        # @param type [String] finds classes called *Nodes::TypeNodes* based on this type
        def resolver_for(type)
          klass_name = "%sNodes" % type.capitalize

          Nodes.const_get(klass_name).new
        rescue NameError
          raise("Cannot find a handler for Node Set type %s" % type)
        end

        def from_hash(data)
          data.each do |nodes, props|
            resolver = resolver_for(props["type"])
            resolver.from_hash(props)
            resolver.validate_configuration!

            node_props = {
              "at_least" => 1,
              "empty_ok" => false,
              "when_empty" => "Did not discover any nodes for nodeset %s" % nodes
            }.merge(props)

            node_props["at_least"] = 0 if node_props["empty_ok"]

            @nodes[nodes] = {
              :resolver => resolver,
              :discovered => [],
              :properties => node_props
            }
          end

          self
        end
      end
    end
  end
end

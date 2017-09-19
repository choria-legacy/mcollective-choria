module MCollective
  module Util
    class Playbook
      class Uses
        def initialize(playbook)
          @playbook = playbook
          @uses = {}
        end

        def [](agent)
          @uses[agent]
        end

        def keys
          @uses.keys
        end

        # Retrieves the agent inventory for a set of nodes
        #
        # @param nodes [Array<String>] list of nodes to retrieve it for
        # @return [Boolean, String, Array] success, message and inventory results
        def agent_inventory(nodes)
          rpc = Tasks::McollectiveTask.new(@playbook)

          rpc.from_hash(
            "nodes" => nodes,
            "action" => "rpcutil.agent_inventory",
            "silent" => true
          )

          success, msg, inventory = rpc.run

          # rpcutil#agent_inventory is a hash in a hash not managed by the DDL
          # this is not handled by the JSON encoding magic that does DDL based
          # symbol and string conversion so we normalise the data always to symbol
          # based structures
          inventory.each do |node|
            node["data"][:agents].each do |agent|
              agent.keys.each do |key| # rubocop:disable Performance/HashEachMethods
                agent[key.intern] = agent.delete(key) if key.is_a?(String)
              end
            end
          end

          [success, msg, inventory]
        end

        # Validates agent versions on nodes
        #
        # @param agents [Hash] a hash of agent names and nodes that uses that agent
        # @raise [StandardError] on failure
        def validate_agents(agents)
          nodes = agents.map {|_, agent_nodes| agent_nodes}.flatten.uniq

          Log.info("Validating agent inventory on %d nodes" % nodes.size)

          validation_fail = false

          success, msg, inventory = agent_inventory(nodes)

          raise("Could not determine agent inventory: %s" % msg) unless success

          agents.each do |agent, agent_nodes|
            unless @uses.include?(agent)
              Log.warn("Agent %s is mentioned in node sets but not declared in the uses list" % agent)
              validation_fail = true
              next
            end

            agent_nodes.each do |node|
              unless node_inventory = inventory.find {|i| i["sender"] == node}
                Log.warn("Did not receive an inventory for node %s" % node)
                validation_fail = true
                next
              end

              unless metadata = node_inventory["data"][:agents].find {|i| i[:agent] == agent}
                Log.warn("Node %s does not have the agent %s" % [node, agent])
                validation_fail = true
                next
              end

              if valid_version?(metadata[:version], @uses[agent])
                Log.debug("Agent %s on %s version %s matches desired version %s" % [agent, node, metadata[:version], @uses[agent]])
              else
                Log.warn("Agent %s on %s version %s does not match desired version %s" % [agent, node, metadata[:version], @uses[agent]])
                validation_fail = true
              end
            end
          end

          raise("Network agents did not match specified SemVer specifications in the playbook") if validation_fail

          Log.info("Agent inventory on %d nodes validated" % nodes.size)
        end

        # Determines if a semver version is within a stated range
        #
        # @note mcollective never suggested semver, so versions like "1.1" becomes "1.1.0" for the compare
        # @param have [String] SemVer of what you have
        # @param want [String] SemVer range of what you need
        # @return [Boolean]
        # @raise [StandardError] on invalid version strings
        def valid_version?(have, want)
          have = "%s.0" % have if have.split(".").size == 2

          semver_have = SemanticPuppet::Version.parse(have)
          semver_want = SemanticPuppet::VersionRange.parse(want)
          semver_want.include?(semver_have)
        end

        # Checks that all the declared agent DDLs exist
        #
        # @raise [StandardError] on invalid DDLs
        def prepare
          invalid = @uses.map do |agent, want|
            begin
              have = ddl_version(agent)

              if valid_version?(have, want)
                Log.debug("Agent %s DDL version %s matches desired %s" % [agent, have, want])
                nil
              else
                Log.warn("Agent %s DDL version %s does not match desired %s" % [agent, have, want])
                agent
              end
            rescue
              Log.warn("Could not process DDL for agent %s: %s: %s" % [agent, $!.class, $!.to_s])
              agent
            end
          end.compact

          raise("DDLs for agent(s) %s did not match desired versions" % invalid.join(", ")) unless invalid.empty?
        end

        # Fetches the DDL version for an agent
        #
        # If the agent DDL has versions like 1.0 it will be
        # turned into 1.0.0 as old mco stuff didnt do semver
        #
        # @param agent [String]
        def ddl_version(agent)
          ddl = agent_ddl(agent)
          ddl.meta[:version]
        end

        # Returns the DDL for a specific agent
        #
        # @param agent [String]
        # @return [DDL::AgentDDL]
        # @raise [StandardError] should the DDL not exist
        def agent_ddl(agent)
          DDL::AgentDDL.new(agent)
        end

        def from_hash(data)
          data.each do |agent, version|
            Log.debug("Loading usage of %s version %s" % [agent, version])
            @uses[agent] = version
          end

          self
        end
      end
    end
  end
end

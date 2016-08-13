module MCollective
  module Util
    class Choria
      class Playbook
        class Nodes
          attr_reader :nodes, :playbook

          def initialize(playbook)
            @nodes = {}
            @nodelists = {}
            @agent_inventory = {}
            @verified = {}
            @playbook = playbook
          end

          def discovered_nodes(set)
            discover! if @nodelists.empty?

            raise("No declared node set '%s'" % set) unless @nodes.include?(set)
            raise("Discovery for node set '%s' found no nodes" % set) unless @nodelists.include?(set)

            @nodelists[set]
          end

          def already_verified?(node, agent)
            return false unless @verified[node]
            @verified[node].fetch(agent, false)
          end

          def mark_verified(node, agent)
            @verified[node] ||= {}
            @verified[node][agent] = true
          end

          def uses
            playbook.uses
          end

          def size
            all_nodes.size
          end

          def all_nodes
            @nodelists.map{|_, hosts| hosts}.flatten.compact.uniq
          end

          def agent_version_for_node(node, agent)
            inventory = @agent_inventory[node]
            agent = inventory.find{|a| a[:agent] == agent}
            agent[:version] if agent
          end

          # this could be a task later?
          def validate_needs!
            fetch_agent_inventory! if @agent_inventory.empty?

            @nodes.each do |node_set, properties|
              nodes = @nodelists[node_set]

              playbook.debug("Verifying agent properties of %d nodes in node set %s" % [nodes.size, node_set])

              Array(properties["needs"]).compact.each do |agent|
                desired = uses.desired(agent)

                playbook.debug("Verifying %s matches %s on %d nodes" % [agent, desired, nodes.size])

                nodes.each do |node|
                  next if already_verified?(node, agent)

                  version = agent_version_for_node(node, agent)

                  raise(DependencyError, "Node %s does not have the %s agent" % [node, agent]) unless version

                  unless uses.covers?(agent, version)
                    raise(DependencyError, "Node %s agent %s version %s does not satisfy the required version %s" % [node, agent, version, desired])
                  end

                  mark_verified(node, agent)

                  playbook.debug("Node %s agent %s version %s satisfies the required version %s" % [node, agent, version, desired])
                end
              end

              playbook.debug("Completed verifying agent properties of %d nodes in node set %s" % [nodes.size, node_set])
            end
          end

          def fetch_agent_inventory!
            discover! if @nodelists.empty?

            playbook.info("Validating agent versions across %d nodes" % size)
            playbook.debug("Fetching agent list from %d nodes" % size)

            client = playbook.rpc_client("rpcutil")
            client.discover(:nodes => all_nodes)
            client.checked_call(:agent_inventory) do |result|
              @agent_inventory[result[:sender]] = result[:data][:agents]
            end
          end

          # this could be a task later?
          def test_connectivity!
            discover! if @nodelists.empty?

            playbook.info("Checking connectivity to %d nodes" % size)
            client = playbook.rpc_client("rpcutil")
            client.discover(:nodes => all_nodes)
            client.checked_call(:ping)
          end

          # might want this to be a task too - it could insert new node lists as a task
          def discover!
            @nodes.each do |nodeset, properties|
              client = playbook.rpc_client("rpcutil")
              if properties["discovery_method"]
                client.discovery_method = properties["discovery_method"]
              end

              client.filter = filter_for(nodeset)
              found = client.discover

              if properties["limit"]
                limit = playbook.t(properties["limit"])

                if limit
                  limit = Integer(limit) - 1
                  found = found[0..limit]
                end
              end

              at_least = Integer(properties.fetch("at_least", 1))

              unless found.size >= at_least
                playbook.warn("Nodeset %s expected at least %d nodes but found %s" % [nodeset, at_least, found.size])

                if properties["when_empty"]
                  msg = playbook.t(properties["when_empty"])
                else
                  msg = "Nodeset %s expected at least %d nodes but found %s" % [nodeset, at_least, found.size]
                end

                raise(TemplateInterprolationError, msg)
              end

              playbook.debug("Nodeset %s found %d nodes using the %s method" % [nodeset, found.size, client.discovery_method])

              @nodelists[nodeset] = found
            end
          end

          def t(string)
            playbook.t(string)
          end

          def filter_for(nodeset)
            raise("Unknown node set %s" % nodeset) unless nodes.include?(nodeset)

            props = nodes[nodeset]
            filter = Util.empty_filter

            if props["facts"]
              Array(props["facts"]).each do |fact|
                filter["fact"] << Util.parse_fact_string(t(fact))
              end
            end

            ["cf_class", "agent", "identity", "compound"].each do |type|
              if props[type]
                Array(props[type]).each do |prop|
                  filter[type] << t(prop)
                end
              end
            end

            filter.each {|k, v| v.compact!}

            if Util.empty_filter?(filter)
              playbook.warn("Filter for node set %s resulted in an empty filter, all nodes will be selected" % nodeset)
            end

            filter
          end

          def from_source(nodes)
            @nodes = nodes
          end
        end
      end
    end
  end
end

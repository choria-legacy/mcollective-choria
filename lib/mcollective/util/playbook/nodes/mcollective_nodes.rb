module MCollective
  module Util
    class Playbook
      class Nodes
        class McollectiveNodes
          def initialize
            @discovery_method = "mc"
            @agents = []
            @facts = []
            @classes = []
            @identity = []
            @compound = nil
          end

          def prepare; end

          # @todo
          def validate_configuration!; end

          # Creates and cache an RPC::Client for the configured agent
          #
          # @param from_cache [Boolean] when false a new instance is always returned
          # @return [RPC::Client]
          def client(from_cache: true)
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
            client = RPC::Client.new(@agents[0], :configfile => Util.config_file_for_user)
            client.progress = false
            client.discovery_method = @discovery_method

            @classes.each do |filter|
              client.class_filter(filter)
            end

            @facts.each do |filter|
              client.fact_filter(filter)
            end

            @agents.each do |filter|
              client.agent_filter(filter)
            end

            @identity.each do |filter|
              client.identity_filter(filter)
            end

            client.compound_filter(@compound) if @compound

            client
          end

          # Initialize the nodes source from a hash
          #
          # @param data [Hash] input data matching nodes.json schema
          # @return [McollectiveNodes]
          def from_hash(data)
            @discovery_method = data.fetch("discovery_method", "mc")
            @agents = data.fetch("agents", ["rpcutil"])
            @facts = data.fetch("facts", [])
            @classes = data.fetch("classes", [])
            @identity = data.fetch("identities", [])
            @compound = data["compound"]

            @_rpc_client = nil

            self
          end

          def discover
            client.discover
          end
        end
      end
    end
  end
end

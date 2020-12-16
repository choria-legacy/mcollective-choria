require "net/http"
require_relative "../util/choria"

module MCollective
  class Discovery
    class Choria
      def self.discover(filter, timeout, limit=0, client=nil)
        Choria.new(filter, timeout, limit, client).discover
      end

      attr_reader :timeout, :limit, :client, :config
      attr_accessor :filter

      def initialize(filter, timeout, limit, client)
        @filter = filter
        @timeout = timeout
        @limit = limit
        @client = client
        @config = Config.instance
      end

      # Search for nodes
      #
      # @return [Array<String>] list of certnames found
      def discover
        queries = []

        if choria.proxied_discovery?
          Log.debug("Performing discovery against a PuppetDB Proxy")

          choria.proxy_discovery_query(proxy_request)
        else
          Log.debug("Performing direct discovery against PuppetDB")
          queries << discover_collective(filter["collective"]) if filter["collective"]
          queries << discover_nodes(filter["identity"]) unless filter["identity"].empty?
          queries << discover_classes(filter["cf_class"]) unless filter["cf_class"].empty?
          queries << discover_facts(filter["fact"]) unless filter["fact"].empty?
          queries << discover_agents(filter["agent"]) unless filter["agent"].empty?

          choria.pql_query(node_search_string(queries.compact), true)
        end
      end

      # Creates a request hash for the discovery proxy
      #
      # @return [Hash]
      def proxy_request
        request = {}

        request["collective"] = filter["collective"] if filter["collective"]
        request["identities"] = filter["identity"] unless filter["identity"].empty?
        request["classes"] = filter["cf_class"] unless filter["cf_class"].empty?
        request["facts"] = filter["fact"] unless filter["fact"].empty?
        request["agents"] = filter["agent"] unless filter["agent"].empty?

        request
      end

      # Discovers nodes in a specific collective
      #
      # @param filter [String] a collective name
      # @return [String] a query string
      def discover_collective(filter)
        'certname in inventory[certname] { facts.mcollective.server.collectives.match("\d+") = "%s" }' % filter
      end

      # Searches for facts
      #
      # Nodes are searched using an `and` operator via the discover_classes method
      #
      # When the `rpcutil` or `scout` agent is required it will look for `Mcollective` class
      # otherwise `Mcollective_avent_agentname` thus it will only find plugins
      # installed using the `choria/mcollective` AIO plugin packager
      #
      # @param filter [Array<String>] agent names
      # @return [Array<String>] list of nodes found
      def discover_agents(filter)
        pql = filter.map do |agent|
          if ["rpcutil", "scout"].include?(agent)
            "(%s or %s)" % [discover_classes(["mcollective::service"]), discover_classes(["choria::service"])]
          elsif agent =~ /^\/(.+)\/$/
            'resources {type = "File" and tag ~ "mcollective_agent_.*?%s.*?_server"}' % [string_regexi($1)]
          else
            'resources {type = "File" and tag = "mcollective_agent_%s_server"}' % [agent]
          end
        end

        pql.join(" and ") unless pql.empty?
      end

      # Turns a string into a case insensitive regex string
      #
      # @param value [String]
      # @return [String]
      def string_regexi(value)
        value =~ /^\/(.+)\/$/ ? derived_value = $1 : derived_value = value.dup

        derived_value.each_char.map do |char|
          if char =~ /[[:alpha:]]/
            "[%s%s]" % [char.downcase, char.upcase]
          else
            char
          end
        end.join
      end

      # Capitalize a Puppet Resource
      #
      # foo::bar => Foo::Bar
      #
      # @param resource [String] a resource title
      # @return [String]
      def capitalize_resource(resource)
        resource.split("::").map(&:capitalize).join("::")
      end

      # Searches for facts
      #
      # Nodes are searched using an `and` operator
      #
      # @param filter [Array<Hash>] hashes with :fact, :operator and :value
      # @return [Array<String>] list of nodes found
      def discover_facts(filter)
        pql = filter.map do |q|
          fact = q[:fact]
          operator = q[:operator]
          value = q[:value]

          case operator
          when "=~"
            regex = string_regexi(value)

            'inventory {facts.%s ~ "%s"}' % [fact, regex]
          when "=="
            if ["true", "false"].include?(value) || numeric?(value)
              'inventory {facts.%s = %s or facts.%s = "%s"}' % [fact, value, fact, value]
            else
              'inventory {facts.%s = "%s"}' % [fact, value]
            end
          when "!="
            if ["true", "false"].include?(value) || numeric?(value)
              'inventory {!(facts.%s = %s or facts.%s = "%s")}' % [fact, value, fact, value]
            else
              'inventory {!(facts.%s = "%s")}' % [fact, value]
            end
          when ">=", ">", "<=", "<"
            raise("Do not know how to do string fact comparisons using the '%s' operator with PuppetDB" % operator) unless numeric?(value)

            "inventory {facts.%s %s %s}" % [fact, operator, value]
          else
            raise("Do not know how to do fact comparisons using the '%s' operator with PuppetDB" % operator)
          end
        end

        pql.join(" and ") unless pql.empty?
      end

      # Searches for classes
      #
      # Nodes are searched using an `and` operator
      #
      # @return [Array<String>] list of nodes found
      def discover_classes(filter)
        pql = filter.map do |klass|
          if klass =~ /^\/(.+)\/$/
            'resources {type = "Class" and title ~ "%s"}' % [string_regexi($1)]
          else
            'resources {type = "Class" and title = "%s"}' % [capitalize_resource(klass)]
          end
        end

        pql.join(" and ") unless pql.empty?
      end

      # Searches for nodes
      #
      # Nodes are searched using an `or` operator
      #
      # @return [Array<String>] list of nodes found
      def discover_nodes(filter)
        if filter.empty?
          Log.debug("Empty node filter found, discovering all nodes")
          nil
        else
          pql = filter.map do |ident|
            if ident =~ /^pql:\s*(.+)$/
              "certname in %s" % $1
            elsif ident =~ /^\/(.+)\/$/
              'certname ~ "%s"' % string_regexi($1)
            else
              'certname = "%s"' % ident
            end
          end

          pql.join(" or ") unless pql.empty?
        end
      end

      # Produce a nodes query with the supplied sub query included
      #
      # @param queries [Array<String>] PQL queries to be used as a sub query
      # @return [String] nodes search string
      def node_search_string(queries)
        filter_queries = queries.map {|q| "(%s)" % q}.join(" and ")

        "nodes[certname, deactivated] { %s }" % [filter_queries]
      end

      # Determines if a string is a number, either float or integer
      #
      # @param string [String]
      # @return [boolean]
      def numeric?(string)
        true if Float(string) rescue false
      end

      def choria
        @_choria ||= Util::Choria.new(false)
      end
    end
  end
end

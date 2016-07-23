module MCollective
  module Util
    class Choria
      # Represents the result from the Puppet `/puppet/v3/environment` endpoint
      class PuppetV3Environment
        attr_reader :application, :site, :site_nodes

        # @param site [Hash] a JSON parsed result from `/puppet/v3/environment`
        def initialize(site, application=nil)
          @site = site
          @application = application
          @site_nodes = node_view

          unless has_runable_nodes?(node_view(false))
            raise(UserError, "Impossible to resolve site catalog found, cannot continue with any instances")
          end
        end

        # Determines if an application is a known one
        #
        # @param application [nil, String] application name
        # @return [Boolean]
        def valid_application?(application)
          return true if application.nil?
          applications.include?(application)
        end

        # List of nodes involved in a specific application
        #
        # @param application [String] an application name like `Lamp[app1]`
        # @return [Array<String>] list of nodes involved in the application
        # @raise [StandardError] when an unknown application is requested
        def application_nodes(application)
          raise(UserError, "Unknown application %s" % application) unless applications.include?(application)

          nodes = site_nodes.select do |_, props|
            props[:applications].include?(application)
          end

          nodes.map {|n, _| n}
        end

        # The environment this app site represents
        #
        # @return [String]
        def environment
          site["environment"]
        end

        # List of known applications in this site
        def applications
          site["applications"].keys.sort
        end

        # Retrieves information about a specific node
        #
        # @example
        #
        #   {
        #     :produces => [],
        #     :consumes => ["Sql[app2]", "Sql[app1]"],
        #     :resources => ["Lamp::Webapp[app2-1]", "Lamp::Webapp[app1-1]"],
        #     :applications => ["Lamp[app2]", "Lamp[app1]"]
        #   }
        #
        # @param name [String] the node name to retrieve
        # @return [Hash,nil]
        def node(name)
          site_nodes[name]
        end

        # List of known nodes in this site involved with applications
        #
        # @return [Array<String>]
        def nodes
          site_nodes.keys.sort
        end

        # Iterates the nodes by groups they need to be run in
        #
        # @yield [Array<String>] nodes capable of being run concurrently
        def each_node_group
          node_groups.each do |group|
            yield(group)
          end
        end

        # Calculate the node run order in groups
        #
        # The array returned is an array of arrays each with the node names
        # included, this represents the order nodes should be run in and are
        # made of up groups to run them in.
        #
        # @see #each_node_group
        # @return [Array<Array<String>>]
        def node_groups
          pending_nodes = node_view
          run_order = []

          until pending_nodes.empty?
            unless has_runable_nodes?(pending_nodes)
              raise(UserError, "Impossible to resolve site catalog found, cannot continue with any instances")
            end

            run_order += extract_runable_nodes!(pending_nodes)
            satisfy_dependencies!(pending_nodes, run_order)
          end

          run_order
        end

        # Calculates a node view from the site as provided by Puppet
        #
        # @api private
        # @return [Hash]
        def node_view(filter=true)
          nodes = {}

          site["applications"].each do |appname, components|
            next if @application && filter && appname != @application

            components.each do |component, props|
              node_name = props["node"]

              nodes[node_name] ||= {
                :produces => [],
                :consumes => [],
                :resources => [],
                :applications => [],
                :application_resources => {}
              }

              nodes[node_name][:produces] += props["produces"]
              nodes[node_name][:consumes] += props["consumes"]
              nodes[node_name][:resources] << component
              nodes[node_name][:applications] << appname
              nodes[node_name][:application_resources][appname] ||= []
              nodes[node_name][:application_resources][appname] << component
            end
          end

          nodes
        end

        # Determines if there are any runable nodes
        #
        # @api private
        # @param nodes [Hash] as produced by node_view
        # @return [Boolean]
        def has_runable_nodes?(nodes)
          !!nodes.find {|_, props| props[:consumes].empty?}
        end

        # Given a list of runnable nodes, extract ones that can be run now
        #
        # @api private
        # @note this will modify the supplied node list removing any that can be run
        # @return [Array<Array<String>>]
        def extract_runable_nodes!(nodes)
          runable = nodes.map {|name, props| name if props[:consumes].empty?}.compact

          nodes.reject! {|name, _| runable.include?(name)}

          [runable]
        end

        # Satisfies dependencies for a list of completed nodes in a list of pending nodes
        #
        # @api private
        # @note this edits the pending nodes removing stuff from their `:consumes` :key
        # @return [void]
        def satisfy_dependencies!(pending_nodes, completed_nodes)
          completed_nodes.flatten.each do |node|
            pending_nodes.each do |_, p_node|
              p_node[:consumes] -= site_nodes[node][:produces]
            end
          end
        end
      end
    end
  end
end

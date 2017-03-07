module MCollective
  module Agent
    class Choria_util < RPC::Agent
      action "info" do
        connector = PluginManager["connector_plugin"]

        reply.fail!("Only support collectives using the Choria NATS connector") unless connector.is_a?(Connector::Nats)

        reply[:security] = config.securityprovider
        reply[:connector] = config.connector
        reply[:client_version] = connector.client_version
        reply[:client_flavour] = connector.client_flavour
        reply[:client_options] = stringify_keys(connector.active_options).reject {|k, _| k == "tls"}
        reply[:client_stats] = stringify_keys(connector.stats)
        reply[:facter_domain] = choria.facter_domain
        reply[:facter_command] = choria.facter_cmd
        reply[:srv_domain] = choria.srv_domain
        reply[:using_srv] = choria.should_use_srv?
        reply[:middleware_servers] = choria.middleware_servers.map {|s| s.join(":")}

        if connector.connected?
          reply[:connected_server] = "%s:%s" % [connector.connected_server.host, connector.connected_server.port]
        else
          reply[:connected_server] = "disconnected"
        end
      end

      def stringify_keys(hash)
        Hash[hash.map {|key, val| [key.to_s, val]}]
      end

      def choria
        @_choria ||= Util::Choria.new("production", nil, false)
      end
    end
  end
end

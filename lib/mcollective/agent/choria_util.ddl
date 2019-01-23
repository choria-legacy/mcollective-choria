metadata    :name        => "choria_util",
            :description => "Choria Utilities",
            :author      => "R.I.Pienaar <rip@devco.net>",
            :license     => "Apache-2.0",
            :version     => "0.13.1",
            :url         => "https://choria.io",
            :timeout     => 20

requires :mcollective => "2.9.0"

action "info", :description => "Choria related information from the running Daemon and Middleware" do
  output :security,
         :description => "Security Provider plugin",
         :display_as => "Security Provider"

  output :secure_protocol,
         :description => "If the protocol is running with PKI security enabled",
         :display_as => "Protocol Secure"

  output :connector,
         :description => "Connector plugin",
         :display_as => "Connector"

  output :connector_tls,
         :description => "If the connector is running with TLS security enabled",
         :display_as => "Connector TLS"

  output :path,
         :description => "Active OS PATH",
         :display_as => "Path"

  output :choria_version,
         :description => "Choria version",
         :display_as => "Choria Version"

  output :client_version,
         :description => "Middleware client library version",
         :display_as => "Middleware Client Library Version"

  output :client_flavour,
         :description => "Middleware client gem flavour",
         :display_as => "Middleware Client Flavour"

  output :client_options,
         :description => "Active Middleware client gem options",
         :display_as => "Middleware Client Options"

  output :connected_server,
         :description => "Connected middleware server",
         :display_as => "Connected Broker"

  output :client_stats,
         :description => "Middleware client gem statistics",
         :display_as => "Middleware Client Stats"

  output :facter_domain,
         :description => "Facter domain",
         :display_as => "Facter Domain"

  output :facter_command,
         :description => "Command used for Facter",
         :display_as => "Facter"

  output :srv_domain,
         :description => "Configured SRV domain",
         :display_as => "SRV Domain"

  output :using_srv,
         :description => "Indicates if SRV records are considered",
         :display_as => "SRV Used"

  output :middleware_servers,
         :description => "Middleware Servers configured or discovered",
         :display_as => "Middleware"

  summarize do
    aggregate summary(:choria_version)
    aggregate summary(:client_version)
    aggregate summary(:client_flavour)
    aggregate summary(:connected_server)
    aggregate summary(:srv_domain)
    aggregate summary(:using_srv)
    aggregate summary(:secure_protocol)
    aggregate summary(:connector_tls)
  end
end

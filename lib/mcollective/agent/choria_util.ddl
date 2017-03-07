metadata    :name        => "choria_util",
            :description => "Choria Utilities",
            :author      => "R.I.Pienaar <rip@devco.net>",
            :license     => "Apache-2.0",
            :version     => "1.0.0",
            :url         => "http:/choria.io",
            :timeout     => 5

requires :mcollective => "2.9.0"

action "info", :description => "Choria related information from the running Daemon and Middleware" do
  output :security,
         :description => "Security Provider plugin",
         :display_as => "Security Provider"

  output :connector,
         :description => "Connector plugin",
         :display_as => "Connector"

  output :client_version,
         :description => "Client gem version",
         :display_as => "Client Version"

  output :client_flavour,
         :description => "Client gem flavour",
         :display_as => "Client Flavour"

  output :client_options,
         :description => "Active client gem options",
         :display_as => "Client Options"

  output :connected_server,
         :description => "Connected middleware server",
         :display_as => "Connected Broker"

  output :client_stats,
         :description => "Client gem statistics",
         :display_as => "Client Stats"

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
    aggregate summary(:client_version)
    aggregate summary(:client_flavour)
    aggregate summary(:connected_server)
    aggregate summary(:srv_domain)
    aggregate summary(:using_srv)
  end
end

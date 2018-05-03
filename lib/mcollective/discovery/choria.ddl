metadata    :name        => "choria",
            :description => "PuppetDB based discovery for the Choria plugin suite",
            :author      => "R.I.Pienaar <rip@devco.net>",
            :license     => "Apache-2.0",
            :version     => "0.8.2",
            :url         => "https://github.com/choria-io",
            :timeout     => 0

discovery do
    capabilities [:classes, :facts, :identity, :agents]
end

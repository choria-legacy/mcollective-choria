require "net/http"
require "resolv"

module MCollective
  module Util
    class Choria
      class UserError < StandardError; end
      class Abort < StandardError; end

      unless defined?(Choria::VERSION) # rubocop:disable Style/IfUnlessModifier
        VERSION = "0.8.2".freeze
      end

      attr_writer :ca

      def initialize(check_ssl=true)
        @config = Config.instance

        check_ssl_setup if check_ssl
      end

      # Creates a new TasksSupport instance with the configured cache dir
      #
      # @return [TasksSupport]
      def tasks_support
        require_relative "tasks_support"

        Util::TasksSupport.new(self, tasks_cache_dir)
      end

      # Determines the Tasks Cache dir
      #
      # @return [String] path to the cache
      def tasks_cache_dir
        if Util.windows?
          File.join(Util.windows_prefix, "tasks-cache")
        elsif Process.uid == 0
          "/opt/puppetlabs/mcollective/tasks-cache"
        else
          File.expand_path("~/.puppetlabs/mcollective/tasks-cache")
        end
      end

      # Determines the Tasks Spool directory
      #
      # @return [String] path to the spool
      def tasks_spool_dir
        if Util.windows?
          File.join(Util.windows_prefix, "tasks-spool")
        elsif Process.uid == 0
          "/opt/puppetlabs/mcollective/tasks-spool"
        else
          File.expand_path("~/.puppetlabs/mcollective/tasks-spool")
        end
      end

      # Which port to provide stats over HTTP on
      #
      # @return [Integer,nil]
      # @raise [StandardError] when not numeric
      def stats_port
        Integer(get_option("choria.stats_port", "")) if has_option?("choria.stats_port")
      end

      # Determines if there are any federations configured
      #
      # @return [Boolean]
      def federated?
        !federation_collectives.empty?
      end

      # List of active collectives that form the federation
      #
      # @return [Array<String>]
      def federation_collectives
        if override_networks = env_fetch("CHORIA_FED_COLLECTIVE", nil)
          override_networks.split(",").map(&:strip).reject(&:empty?)
        else
          get_option("choria.federation.collectives", "").split(",").map(&:strip).reject(&:empty?)
        end
      end

      # Retrieves a DNS resolver
      #
      # @note mainly used for testing
      # @return [Resolv::DNS]
      def resolver
        Resolv::DNS.new
      end

      # Retrieves the domain from facter networking.domain if facter is found
      #
      # Potentially we could use the local facts in mcollective but that's a chicken
      # and egg and sometimes its only set after initial connection if something like
      # a cron job generates the yaml cache file
      #
      # @return [String,nil]
      def facter_domain
        if path = facter_cmd
          `"#{path}" networking.domain`.chomp
        end
      end

      # Determines the domain to do SRV lookups in
      #
      # This is settable using choria.srv_domain and defaults
      # to the domain as reported by facter
      #
      # @return [String]
      def srv_domain
        get_option("choria.srv_domain", nil) || facter_domain
      end

      # Determines the SRV records to look up
      #
      # If an option choria.srv_domain is set that will be used else facter will be consulted,
      # if neither of those provide a domain name a empty list is returned
      #
      # @param keys [Array<String>] list of keys to lookup
      # @return [Array<String>] list of SRV records
      def srv_records(keys)
        domain = srv_domain

        if domain.nil? || domain.empty?
          Log.warn("Cannot look up SRV records, facter is not functional and choria.srv_domain was not supplied")
          return []
        end

        keys.map do |key|
          "%s.%s" % [key, domain]
        end
      end

      # Determines if SRV records should be used
      #
      # Setting choria.use_srv_records to anything other than t, true, yes or 1 will disable
      # SRV records
      #
      # @return [Boolean]
      def should_use_srv?
        ["t", "true", "yes", "1"].include?(get_option("choria.use_srv_records", "1").downcase)
      end

      # Query DNS for a series of records
      #
      # The given records will be passed through {#srv_records} to figure out the domain to query in.
      #
      # Querying of records can be bypassed by setting choria.use_srv_records to false
      #
      # @yield [Hash] each record for modification by the caller
      # @param records [Array<String>] the records to query without their domain parts
      # @return [Array<Hash>] with keys :port, :priority, :weight and :target
      def query_srv_records(records)
        unless should_use_srv?
          Log.info("Skipping SRV record queries due to choria.query_srv_records setting")
          return []
        end

        answers = Array(srv_records(records)).map do |record|
          Log.debug("Attempting to resolve SRV record %s" % record)
          answers = resolver.getresources(record, Resolv::DNS::Resource::IN::SRV)
          Log.debug("Found %d SRV records for %s" % [answers.size, record])
          answers
        end.flatten

        answers = answers.sort_by(&:priority).chunk(&:priority).sort
        answers = sort_srv_answers(answers)

        answers.map do |result|
          Log.debug("Found %s:%s with priority %s and weight %s" % [result.target, result.port, result.priority, result.weight])

          ans = {
            :port => result.port,
            :priority => result.priority,
            :weight => result.weight,
            :target => result.target
          }

          yield(ans) if block_given?

          ans
        end
      end

      # Sorts SRV records according to rfc2782
      #
      # @note this is probably still not correct :( so horrible
      # @param answers [Array<Resolv::DNS::Resource::IN::SRV>]
      # @return [Array<Resolv::DNS::Resource::IN::SRV>] sorted records
      def sort_srv_answers(answers)
        sorted_answers = []

        # this is roughly based on the resolv-srv and supposedly mostly rfc2782 compliant
        answers.each do |_, available| # rubocop:disable Performance/HashEachMethods
          total_weight = available.inject(0) {|a, e| a + e.weight + 1 }

          until available.empty?
            selector = Integer(rand * total_weight) + 1
            selected_idx = available.find_index do |e|
              selector -= e.weight + 1
              selector <= 0
            end
            selected = available.delete_at(selected_idx)

            total_weight -= selected.weight + 1

            sorted_answers << selected
          end
        end

        sorted_answers
      end

      # Create a Net::HTTP instance optionally set up with the Puppet certs
      #
      # If the client_private_key and client_public_cert both exist they will
      # be used to validate the connection
      #
      # If the ca_path exist it will be used and full verification will be enabled
      #
      # @param server [Hash] as returned by {#try_srv}
      # @param force_puppet_ssl [boolean] when true will call {#check_ssl_setup} and so force Puppet certs
      # @return [Net::HTTP]
      def https(server, force_puppet_ssl=false)
        Log.debug("Creating new HTTPS connection to %s:%s" % [server[:target], server[:port]])

        check_ssl_setup if force_puppet_ssl

        http = Net::HTTP.new(server[:target], server[:port])

        http.use_ssl = true

        if has_client_private_key? && has_client_public_cert?
          http.cert = OpenSSL::X509::Certificate.new(File.read(client_public_cert))
          http.key = OpenSSL::PKey::RSA.new(File.read(client_private_key))
        end

        if has_ca?
          http.ca_file = ca_path
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        else
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end

        http
      end

      # Creates a Net::HTTP::Get instance for a path that defaults to accepting JSON
      #
      # @param path [String]
      # @return [Net::HTTP::Get]
      def http_get(path, headers=nil)
        headers ||= {}
        headers = {
          "Accept" => "application/json",
          "User-Agent" => "Choria version %s http://choria.io" % VERSION
        }.merge(headers)

        Net::HTTP::Get.new(path, headers)
      end

      # Does a proxied discovery request
      #
      # @param query [Hash] Discovery query as per pdbproxy standard
      # @return [Array] JSON parsed result set
      # @raise [StandardError] on any failures
      def proxy_discovery_query(query)
        transport = https(discovery_server, true)
        request = http_get("/v1/discover")
        request.body = query.to_json
        request["Content-Type"] = "application/json"

        resp, data = transport.request(request)

        raise("Failed to make request to Discovery Proxy: %s: %s" % [resp.code, resp.body]) unless resp.code == "200"

        result = JSON.parse(data || resp.body)

        result["nodes"]
      end

      # Extract certnames from PQL results, deactivated nodes are ignored
      #
      # @param results [Array]
      # @return [Array<String>] list of certnames
      def pql_extract_certnames(results)
        results.reject {|n| n["deactivated"]}.map {|n| n["certname"]}.compact
      end

      # Performs a PQL query against the configured PuppetDB
      #
      # @param query [String] PQL Query
      # @param only_certnames [Boolean] extract certnames from the results
      # @return [Array] JSON parsed result set
      # @raise [StandardError] on any failures
      def pql_query(query, only_certnames=false)
        Log.debug("Performing PQL query: %s" % query)

        path = "/pdb/query/v4?%s" % URI.encode_www_form("query" => query)

        resp, data = https(puppetdb_server, true).request(http_get(path))

        raise("Failed to make request to PuppetDB: %s: %s: %s" % [resp.code, resp.message, resp.body]) unless resp.code == "200"

        result = JSON.parse(data || resp.body)

        Log.debug("Found %d records for query %s" % [result.size, query])

        only_certnames ? pql_extract_certnames(result) : result
      end

      # Checks if all the required SSL files exist
      #
      # @param log [Boolean] log warnings when true
      # @return [Boolean]
      def have_ssl_files?(log=true)
        [client_public_cert, client_private_key, ca_path].map do |path|
          Log.debug("Checking for SSL file %s" % path)

          if File.exist?(path)
            true
          else
            Log.warn("Cannot find SSL file %s" % path) if log
            false
          end
        end.all?
      end

      # Validates a certificate against the CA
      #
      # @param pubcert [String] PEM encoded X509 public certificate
      # @param log [Boolean] log warnings when true
      # @return [String,false] when succesful, the certname else false
      # @raise [StandardError] in case OpenSSL fails to open the various certificates
      # @raise [OpenSSL::X509::CertificateError] if the CA is invalid
      def valid_certificate?(pubcert, log=true)
        unless File.readable?(ca_path)
          raise("Cannot find or read the CA in %s, cannot verify public certificate" % ca_path)
        end

        incoming = parse_pubcert(pubcert, log)

        return false unless incoming

        begin
          ca = OpenSSL::X509::Certificate.new(File.read(ca_path))
        rescue OpenSSL::X509::CertificateError
          Log.warn("Failed to load CA from %s: %s: %s" % [ca_path, $!.class, $!.to_s]) if log
          raise
        end

        unless incoming.issuer.to_s == ca.subject.to_s && incoming.verify(ca.public_key)
          Log.warn("Failed to verify certificate %s against CA %s in %s" % [incoming.subject.to_s, ca.subject.to_s, ca_path]) if log
          return false
        end

        Log.debug("Verified certificate %s against CA %s" % [incoming.subject.to_s, ca.subject.to_s]) if log

        cn_parts = incoming.subject.to_a.select {|c| c[0] == "CN"}.flatten

        raise("Could not parse certificate with subject %s as it has no CN part" % [incoming.subject.to_s]) if cn_parts.empty?

        cn_parts[1]
      end

      # Parses a public cert
      #
      # @param pubcert [String] PEM encoded public certificate
      # @param log [Boolean] log warnings when true
      # @return [OpenSSL::X509::Certificate,nil]
      def parse_pubcert(pubcert, log=true)
        OpenSSL::X509::Certificate.new(pubcert)
      rescue OpenSSL::X509::CertificateError
        Log.warn("Received certificate is not a valid x509 certificate: %s: %s" % [$!.class, $!.to_s]) if log
        nil
      end

      # Checks all the required SSL files exist
      #
      # @param log [Boolean] log warnings when true
      # @return [Boolean]
      # @raise [StandardError] on failure
      def check_ssl_setup(log=true)
        if Process.uid == 0 && PluginManager["security_plugin"].initiated_by == :client
          raise(UserError, "The Choria client cannot be run as root")
        end

        raise(UserError, "Not all required SSL files exist") unless have_ssl_files?(log)

        embedded_certname = nil

        begin
          embedded_certname = valid_certificate?(File.read(client_public_cert))
        rescue
          raise(UserError, "The public certificate was not signed by the configured CA")
        end

        unless embedded_certname == certname
          raise(UserError, "The certname %s found in %s does not match the configured certname of %s" % [embedded_certname, client_public_cert, certname])
        end

        true
      end

      # Resolves server lists based on config and SRV records
      #
      # Attempts to find server in the following order:
      #
      #   * Configured hosts in `config_option`
      #   * SRV lookups of `srv_records`
      #   * Defaults
      #   * nil otherwise
      #
      # @param config_option [String] config to lookup
      # @param srv_records [Array<String>] list of SRV records to query
      # @param default_host [String] host to use when not found
      # @param default_port [String] port to use when not found
      # @return [Array, nil] groups of host and port pairs
      def server_resolver(config_option, srv_records, default_host=nil, default_port=nil)
        if servers = get_option(config_option, nil)
          hosts = servers.split(",").map do |server|
            server.split(":").map(&:strip)
          end

          return hosts
        end

        srv_answers = query_srv_records(srv_records)

        unless srv_answers.empty?
          hosts = srv_answers.map do |answer|
            [answer[:target], answer[:port]]
          end

          return hosts
        end

        [[default_host, default_port]] if default_host && default_port
      end

      # Finds the middleware hosts in config or DNS
      #
      # Attempts to find servers in the following order:
      #
      #  * Any federation servers if in a federation
      #  * Configured hosts in choria.middleware_hosts
      #  * SRV lookups in _mcollective-server._tcp and _x-puppet-mcollective._tcp
      #  * Supplied defaults
      #
      # Eventually it's intended that other middleware might be supported
      # this would provide a single way to configure them all
      #
      # @param default_host [String] default hostname
      # @param default_port [String] default port
      # @return [Array<Array<String, String>>] groups of host and port
      def middleware_servers(default_host="puppet", default_port="4222")
        if federated? && federation = federation_middleware_servers
          return federation
        end

        server_resolver("choria.middleware_hosts", ["_mcollective-server._tcp", "_x-puppet-mcollective._tcp"], default_host, default_port)
      end

      # Looks for federation middleware servers when federated
      #
      # Attempts to find servers in the following order:
      #
      #  * Configured hosts in choria.federation_middleware_hosts
      #  * SRV lookups in _mcollective-federation_server._tcp and _x-puppet-mcollective_federation._tcp
      #
      # @note you'd still want to only get your middleware servers from {#middleware_servers}
      # @return [Array,nil] groups of host and port, nil when not found
      def federation_middleware_servers
        server_resolver("choria.federation_middleware_hosts", ["_mcollective-federation_server._tcp", "_x-puppet-mcollective_federation._tcp"])
      end

      # Determines if servers should be randomized
      #
      # @return [Boolean]
      def randomize_middleware_servers?
        Util.str_to_bool(get_option("choria.randomize_middleware_hosts", "false"))
      end

      # Attempts to look up some SRV records falling back to defaults
      #
      # When given a array of multiple names it will try each name individually
      # and check if it resolved to a answer, if it did it will use that one.
      # Else it will move to the next.  In this way you can prioritise one
      # record over another like puppetdb over puppet and faill back to defaults.
      #
      # This is a pretty naive implementation that right now just returns
      # the first result, the correct behaviour needs to be determined but
      # for now this gets us going with easily iterable code.
      #
      # These names are mainly being used by {#https} so in theory it would
      # be quite easy to support multiple results with fall back etc, but
      # I am not really sure what would be the best behaviour here
      #
      # @param names [Array<String>, String] list of names to lookup without the domain
      # @param default_target [String] default for the returned :target
      # @param default_port [String] default for the returned :port
      # @return [Hash] with :target and :port
      def try_srv(names, default_target, default_port)
        srv_answers = Array(names).map do |name|
          answer = query_srv_records([name])

          answer.empty? ? nil : answer
        end.compact.flatten

        if srv_answers.empty?
          {:target => default_target, :port => default_port}
        else
          {:target => srv_answers[0][:target].to_s, :port => srv_answers[0][:port]}
        end
      end

      # The Puppet server to connect to
      #
      # Will consult SRV records for _x-puppet._tcp.example.net first then
      # configurable using choria.puppetserver_host and choria.puppetserver_port
      # defaults to puppet:8140.
      #
      # @return [Hash] with :target and :port
      def puppet_server
        d_host = get_option("choria.puppetserver_host", "puppet")
        d_port = get_option("choria.puppetserver_port", "8140")

        try_srv(["_x-puppet._tcp"], d_host, d_port)
      end

      # The Puppet server to connect to
      #
      # Will consult _x-puppet-ca._tcp.example.net then _x-puppet._tcp.example.net
      # then configurable using choria.puppetca_host, defaults to puppet:8140
      #
      # @return [Hash] with :target and :port
      def puppetca_server
        d_port = get_option("choria.puppetca_port", "8140")

        if @ca
          {:target => @ca, :port => d_port}
        else
          d_host = get_option("choria.puppetca_host", "puppet")
          try_srv(["_x-puppet-ca._tcp", "_x-puppet._tcp"], d_host, d_port)
        end
      end

      # The PuppetDB server to connect to
      #
      # Will consult _x-puppet-db._tcp.example.net then _x-puppet._tcp.example.net
      # then configurable using choria.puppetdb_host and choria.puppetdb_port, defaults
      # to puppet:8081
      #
      # @return [Hash] with :target and :port
      def puppetdb_server
        d_host = get_option("choria.puppetdb_host", "puppet")
        d_port = get_option("choria.puppetdb_port", "8081")

        answer = try_srv(["_x-puppet-db._tcp", "_x-puppet._tcp"], d_host, d_port)

        # In the case where we take _x-puppet._tcp SRV records we unfortunately have
        # to force the port else it uses the one from Puppet which will 404
        answer[:port] = d_port

        answer
      end

      # Looks for discovery proxy servers
      #
      # Attempts to find servers in the following order:
      #
      #  * If choria.discovery_proxy is set to false, returns nil
      #  * Configured hosts in choria.discovery_proxies
      #  * SRV lookups in _mcollective-discovery._tcp
      #
      # @return [Hash] with :target and :port
      def discovery_server
        return unless proxied_discovery?

        d_host = get_option("choria.discovery_host", "puppet")
        d_port = get_option("choria.discovery_port", "8085")

        try_srv(["_mcollective-discovery._tcp"], d_host, d_port)
      end

      # Determines if this is using a discovery proxy
      #
      # @return [Boolean]
      def proxied_discovery?
        has_option?("choria.discovery_host") || has_option?("choria.discovery_port") || Util.str_to_bool(get_option("choria.discovery_proxy", "false"))
      end

      # The certname of the current context
      #
      # In the case of root that would be the configured `identity`
      # for non root it would a string made up of the current username
      # as determined by the USER environment variable or the configured
      # `identity`
      #
      # At present windows clients are probably not supported automatically
      # as they will default to the certificate based on identity.  Same
      # as root.  Windows will have to rely on the environment override
      # until we can figure out what the best behaviour is
      #
      # In all cases the certname can be overridden using the `MCOLLECTIVE_CERTNAME`
      # environment variable
      #
      # @return [String]
      def certname
        if Process.uid == 0 || Util.windows?
          certname = @config.identity
        else
          certname = "%s.mcollective" % [env_fetch("USER", @config.identity)]
        end

        env_fetch("MCOLLECTIVE_CERTNAME", certname)
      end

      # Initialises Puppet if needed and retrieve a config setting
      #
      # @param setting [Symbol] a Puppet setting name
      # @return [String]
      def puppet_setting(setting)
        require "puppet"

        unless Puppet.settings.app_defaults_initialized?
          Puppet.settings.preferred_run_mode = :agent

          Puppet.settings.initialize_global_settings([])
          Puppet.settings.initialize_app_defaults(Puppet::Settings.app_defaults_for_run_mode(Puppet.run_mode))
          Puppet.push_context(Puppet.base_context(Puppet.settings))
        end

        Puppet.settings[setting]
      end

      # Creates a SSL Context which includes the AIO SSL files
      #
      # @return [OpenSSL::SSL::SSLContext]
      def ssl_context
        context = OpenSSL::SSL::SSLContext.new
        context.ca_file = ca_path
        context.cert = OpenSSL::X509::Certificate.new(File.read(client_public_cert))
        context.key = OpenSSL::PKey::RSA.new(File.read(client_private_key))
        context.verify_mode = OpenSSL::SSL::VERIFY_PEER

        context
      end

      # The directory where SSL related files live
      #
      # This is configurable using choria.ssldir which should be a
      # path expandable using File.expand_path
      #
      # On Windows or when running as root Puppet settings will be consulted
      # but when running as a normal user it will default to the AIO path
      # when not configured
      #
      # @return [String]
      def ssl_dir
        @__ssl_dir ||= if has_option?("choria.ssldir")
                         File.expand_path(get_option("choria.ssldir"))
                       elsif Util.windows? || Process.uid == 0
                         puppet_setting(:ssldir)
                       else
                         File.expand_path("~/.puppetlabs/etc/puppet/ssl")
                       end
      end

      # The path to a client public certificate
      #
      # @note paths determined by Puppet AIO packages
      # @return [String]
      def client_public_cert
        File.join(ssl_dir, "certs", "%s.pem" % certname)
      end

      # Determines if teh client_public_cert exist
      #
      # @return [Boolean]
      def has_client_public_cert?
        File.exist?(client_public_cert)
      end

      # The path to a client private key
      #
      # @note paths determined by Puppet AIO packages
      # @return [String]
      def client_private_key
        File.join(ssl_dir, "private_keys", "%s.pem" % certname)
      end

      # Determines if the client_private_key exist
      #
      # @return [Boolean]
      def has_client_private_key?
        File.exist?(client_private_key)
      end

      # The path to the CA
      #
      # @return [String]
      def ca_path
        File.join(ssl_dir, "certs", "ca.pem")
      end

      # Determines if the CA exist
      #
      # @return [Boolean]
      def has_ca?
        File.exist?(ca_path)
      end

      # The path to a CSR for this user
      #
      # @return [String]
      def csr_path
        File.join(ssl_dir, "certificate_requests", "%s.pem" % certname)
      end

      # Determines if the CSR exist
      #
      # @return [Boolean]
      def has_csr?
        File.exist?(csr_path)
      end

      # Searches the PATH for an executable command
      #
      # @param command [String] a command to search for
      # @return [String,nil] the path to the command or nil
      def which(command)
        exts = Array(env_fetch("PATHEXT", "").split(";"))
        exts << "" if exts.empty?

        env_fetch("PATH", "").split(File::PATH_SEPARATOR).each do |path|
          exts.each do |ext|
            exe = File.join(path, "%s%s" % [command, ext])
            return exe if File.executable?(exe) && !File.directory?(exe)
          end
        end

        nil
      end

      # Searches the machine for a working facter
      #
      # It checks AIO path first and then attempts to find it in PATH and supports both
      # unix and windows
      #
      # @return [String,nil]
      def facter_cmd
        return "/opt/puppetlabs/bin/facter" if File.executable?("/opt/puppetlabs/bin/facter")

        which("facter")
      end

      # Creates any missing SSL directories
      #
      # This prepares a Puppet like SSL tree in case Puppet
      # has not been initialized yet
      #
      # @return [void]
      def make_ssl_dirs
        FileUtils.mkdir_p(ssl_dir, :mode => 0o0771)

        ["certificate_requests", "certs", "public_keys"].each do |dir|
          FileUtils.mkdir_p(File.join(ssl_dir, dir), :mode => 0o0755)
        end

        ["private_keys", "private"].each do |dir|
          FileUtils.mkdir_p(File.join(ssl_dir, dir), :mode => 0o0750)
        end
      end

      # Creates a RSA key of a certain strenth
      #
      # @return [OpenSSL::PKey::RSA]
      def create_rsa_key(bits)
        OpenSSL::PKey::RSA.new(bits)
      end

      # Writes a new 4096 bit key in the puppet default locatioj
      #
      # @return [OpenSSL::PKey::RSA]
      # @raise [StandardError] when the key already exist
      def write_key
        if has_client_private_key?
          raise("Refusing to overwrite existing key in %s" % client_private_key)
        end

        key = create_rsa_key(4096)
        File.open(client_private_key, "w", 0o0640) {|f| f.write(key.to_pem)}

        key
      end

      # Creates a basic CSR
      #
      # @return [OpenSSL::X509::Request] signed CSR
      def create_csr(cn, ou, key)
        csr = OpenSSL::X509::Request.new
        csr.version = 0
        csr.public_key = key.public_key
        csr.subject = OpenSSL::X509::Name.new(
          [
            ["CN", cn, OpenSSL::ASN1::UTF8STRING],
            ["OU", ou, OpenSSL::ASN1::UTF8STRING]
          ]
        )
        csr.sign(key, OpenSSL::Digest::SHA1.new)

        csr
      end

      # Creates a new CSR signed by the given key
      #
      # @param key [OpenSSL::PKey::RSA]
      # @return [String] PEM encoded CSR
      def write_csr(key)
        raise("Refusing to overwrite existing CSR in %s" % csr_path) if has_csr?

        csr = create_csr(certname, "mcollective", key)

        File.open(csr_path, "w", 0o0644) {|f| f.write(csr.to_pem)}

        csr.to_pem
      end

      # Fetch and save the CA from Puppet
      #
      # @return [Boolean]
      def fetch_ca
        return true if has_ca?

        server = puppetca_server

        req = http_get("/puppet-ca/v1/certificate/ca?environment=production", "Accept" => "text/plain")
        resp, _ = https(server).request(req)

        if resp.code == "200"
          File.open(ca_path, "w", 0o0644) {|f| f.write(resp.body)}
        else
          raise(UserError, "Failed to fetch CA from %s:%s: %s: %s" % [server[:target], server[:port], resp.code, resp.message])
        end

        has_ca?
      end

      # Requests a certificate from the Puppet CA
      #
      # This will attempt to create a new key, write a CSR and
      # then sends it to the CA for signing
      #
      # @return [Boolean]
      # @raise [UserError] when requesting the cert fails
      def request_cert
        key = write_key
        csr = write_csr(key)

        server = puppetca_server

        req = Net::HTTP::Put.new("/puppet-ca/v1/certificate_request/%s?environment=production" % certname, "Content-Type" => "text/plain")
        req.body = csr
        resp, _ = https(server).request(req)

        if resp.code == "200"
          true
        else
          raise(UserError, "Failed to request certificate from %s:%s: %s: %s: %s" % [server[:target], server[:port], resp.code, resp.message, resp.body])
        end
      end

      # Attempts to fetch a cert from the CA
      #
      # @return [Boolean]
      def attempt_fetch_cert
        return true if has_client_public_cert?

        req = http_get("/puppet-ca/v1/certificate/%s?environment=production" % certname, "Accept" => "text/plain")
        resp, _ = https(puppetca_server).request(req)

        if resp.code == "200"
          File.open(client_public_cert, "w", 0o0644) {|f| f.write(resp.body)}
          true
        else
          false
        end
      end

      # Determines if a CSR has been sent but not yet retrieved
      #
      # @return [Boolean]
      def waiting_for_cert?
        !has_client_public_cert? && has_client_private_key?
      end

      # Gets a config option
      #
      # @param opt [String] config option to look up
      # @param default [Object] default to return when not found
      # @return [Object, Proc] the found data or default. When it's a proc the proc will be called only when needed
      # @raise [StandardError] when no default is given and option is not found
      def get_option(opt, default=:_unset)
        return @config.pluginconf[opt] if has_option?(opt)

        unless default == :_unset
          if default.is_a?(Proc)
            return default.call
          else
            return default
          end
        end

        raise(UserError, "No plugin.%s configuration option given" % opt)
      end

      # Determines if a config option is set
      #
      # @param opt [String] config option to look up
      # @return [Boolean]
      def has_option?(opt)
        @config.pluginconf.include?(opt)
      end

      def env_fetch(key, default=nil)
        ENV.fetch(key, default)
      end
    end
  end
end

require_relative "choria/puppet_v3_environment"
require_relative "choria/orchestrator"

require "net/http"
require "resolv"

module MCollective
  module Util
    class Choria
      class UserError < StandardError; end
      class Abort < StandardError; end

      attr_writer :ca

      def initialize(environment, application=nil, check_ssl=true)
        @environment = environment
        @application = application
        @config = Config.instance

        check_ssl_setup if check_ssl
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

      # Query DNS for a series of records
      #
      # The given records will be passed through {#srv_records} to figure out the domain to query in
      #
      # @yield [Hash] each record for modification by the caller
      # @param records [Array<String>] the records to query without their domain parts
      # @return [Array<Hash>] with keys :port, :priority, :weight and :target
      def query_srv_records(records)
        answers = Array(srv_records(records)).map do |record|
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
        answers.each do |_, available|
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

      # Wrapper around site data
      #
      # @return [PuppetV3Environment]
      def puppet_environment
        # at present only 1 format supported, but this will change
        # soon with an additional format, here I guess we will detect
        # the different version of the site data and load the right
        # wrapper class
        #
        # For now there is only only
        PuppetV3Environment.new(fetch_environment, @application)
      end

      # Orchastrator for Puppet Environment Data
      #
      # @param client [MCollective::RPC::Client] client set up for the puppet agent
      # @param batch_size [Integer] batch size to run nodes in
      # @return [Orchestrator]
      def orchestrator(client, batch_size)
        Orchestrator.new(self, client, batch_size)
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

      # Creates a JSON accepting Net::HTTP::Get instance for a path
      #
      # @param path [String]
      # @return [Net::HTTP::Get]
      def http_get(path)
        Net::HTTP::Get.new(path, "Accept" => "application/json")
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

      # Fetch the environment data from `/puppet/v3/environment`
      #
      # @return [Hash] site data
      def fetch_environment
        path = "/puppet/v3/environment/%s" % @environment
        resp, data = https(puppet_server).request(http_get(path))

        raise(UserError, "Failed to make request to Puppet: %s: %s: %s" % [resp.code, resp.message, resp.body]) unless resp.code == "200"

        JSON.parse(data || resp.body)
      end

      # Checks all the required SSL files exist
      #
      # @return [boolean]
      # @raise [StandardError] on failure
      def check_ssl_setup
        valid = [client_public_cert, client_private_key, ca_path].map do |path|
          Log.debug("Checking for SSL file %s" % path)

          if File.exist?(path)
            true
          else
            Log.warn("Cannot find SSL file %s" % path)
            false
          end
        end.all?

        raise(UserError, "Client SSL is not correctly setup, please use 'mco choria request_cert'") unless valid

        true
      end

      # Finds the middleware hosts in config or DNS
      #
      # Attempts to find servers in the following order:
      #
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
      def middleware_servers(default_host, default_port)
        if servers = get_option("choria.middleware_hosts", nil)
          hosts = servers.split(",").map do |server|
            server.split(":")
          end

          return hosts
        end

        srv_answers = query_srv_records(["_mcollective-server._tcp", "_x-puppet-mcollective._tcp"])

        unless srv_answers.empty?
          hosts = srv_answers.map do |answer|
            [answer[:target], answer[:port]]
          end

          return hosts
        end

        [[default_host, default_port]]
      end

      # Attempts to look up some SRV records falling back to defaults
      #
      # This is a pretty naive implementation that right now just returns
      # the first result, the correct behaviour needs to be determined but
      # for now this gets us going with easily iterable code.
      #
      # These names are mainly being used by {#https} so in theory it would
      # be quite easy to support multiple results with fall back etc, but
      # I am not really sure what would be the best behaviour here
      #
      # @param names [Array<String>] list of names to lookup without the domain
      # @param default_target [String] default for the returned :target
      # @param default_port [String] default for the returned :port
      # @return [Hash] with :target and :port
      def try_srv(names, default_target, default_port)
        srv_answers = query_srv_records(names)

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
        if @ca
          {:target => @ca, :port => "8140"}
        else
          d_host = get_option("choria.puppetca_host", "puppet")
          try_srv(["_x-puppet-ca._tcp", "_x-puppet._tcp"], d_host, "8140")
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

      # The certname of the current context
      #
      # In the case of root that would be the configured `identity`
      # for non root it would a string made up of the current username
      # as determined by the USER environment variable or the configured
      # `identity`
      #
      # In all cases the certname can be overridden using the `MCOLLECTIVE_CERTNAME`
      # environment variable
      #
      # @return [String]
      def certname
        if Process.uid == 0
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

      # The directory where SSL related files live
      #
      # This is configurable using choria.ssldir which should be a
      # path expandable using {File.expand_path}
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

      # Searches the machine for a working facter
      #
      # It checks AIO path first and then attempts to find it in PATH and supports both
      # unix and windows
      #
      # @return [String,nil]
      def facter_cmd
        return "/opt/puppetlabs/bin/facter" if File.executable?("/opt/puppetlabs/bin/facter")

        exts = Array(env_fetch("PATHEXT", "").split(";"))
        exts << "" if exts.empty?

        env_fetch("PATH", "").split(File::PATH_SEPARATOR).each do |path|
          exts.each do |ext|
            exe = File.join(path, "%s%s" % ["facter", ext])
            return exe if File.executable?(exe) && !File.directory?(exe)
          end
        end

        nil
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

        req = Net::HTTP::Get.new("/puppet-ca/v1/certificate/ca", "Content-Type" => "text/plain")
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

        req = Net::HTTP::Get.new("/puppet-ca/v1/certificate/%s" % certname, "Accept" => "text/plain")
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

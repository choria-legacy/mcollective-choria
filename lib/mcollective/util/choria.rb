require_relative "choria/puppet_v3_environment"
require_relative "choria/orchestrator"
require "net/http"

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
      # @return [Net::HTTP]
      def https(server=puppet_server, port=puppet_port)
        http = Net::HTTP.new(server, port)

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

      # Fetch the environment data from `/puppet/v3/environment`
      #
      # @return [Hash] site data
      def fetch_environment
        path = "/puppet/v3/environment/%s" % @environment
        resp, data = https.request(http_get(path))

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

      # The Puppet server to connect to
      #
      # Configurable using choria.puppetserver_host, defaults to puppet
      #
      # @todo also support SRV
      # @return [String]
      def puppet_server
        get_option("choria.puppetserver_host", "puppet")
      end

      # The Puppet server port to connect to
      #
      # Configurable using choria.puppetserver_port, defaults to 8140
      #
      # @note this has to be a the SSL port, plain text is not supported
      # @return [String]
      def puppet_port
        get_option("choria.puppetserver_port", "8140")
      end

      # The Puppet server to connect to
      #
      # Configurable using choria.puppetca_host, defaults to puppet
      #
      # @todo also support SRV
      # @return [String]
      def puppetca_server
        @ca || get_option("choria.puppetca_host", "puppet")
      end

      # The PuppetDB server to connect to
      #
      # Configurable using choria.puppetdb_host, defaults to puppet
      #
      # @return [String]
      def puppetdb_server
        get_option("choria.puppetdb_host", "puppet")
      end

      # The PuppetDB server port to connect to
      #
      # Configurable using choria.puppetdb_port, defaults to 8081
      #
      # @note this has to be a the SSL port, plain text is not supported
      # @return [String]
      def puppetdb_port
        get_option("choria.puppetdb_port", "8081")
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

      # The directory where SSL related files live
      #
      # This differs between root (usually the daemon) and non root
      # (usually the client) and follow the conventions of Puppet AIO
      # packages
      #
      # @return [String]
      def ssl_dir
        if Util.windows?
          'C:\ProgramData\PuppetLabs\puppet\etc\ssl'
        elsif Process.uid == 0
          "/etc/puppetlabs/puppet/ssl"
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
      # @retrun [String] PEM encoded CSR
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

        req = Net::HTTP::Get.new("/puppet-ca/v1/certificate/ca", "Content-Type" => "text/plain")
        resp, _ = https(puppetca_server).request(req)

        if resp.code == "200"
          File.open(ca_path, "w", 0o0644) {|f| f.write(resp.body)}
        else
          raise(UserError, "Failed to fetch CA from %s: %s: %s" % [puppetca_server, resp.code, resp.message])
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

        req = Net::HTTP::Put.new("/puppet-ca/v1/certificate_request/%s?environment=production" % certname, "Content-Type" => "text/plain")
        req.body = csr
        resp, _ = https(puppetca_server).request(req)

        if resp.code == "200"
          true
        else
          raise(UserError, "Failed to request certificate from %s: %s: %s: %s" % [puppetca_server, resp.code, resp.message, resp.body])
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
      # @return [Object] the found data or default
      # @raise [StandardError] when no default is given and option is not found
      def get_option(opt, default=:_unset)
        return @config.pluginconf[opt] if @config.pluginconf.include?(opt)
        return default unless default == :_unset

        raise(UserError, "No plugin.%s configuration option given" % opt)
      end

      def env_fetch(key, default=nil)
        ENV.fetch(key, default)
      end
    end
  end
end

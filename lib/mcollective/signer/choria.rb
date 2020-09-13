require_relative "base"

module MCollective
  module Signer
    # This is a Secure Request Signer that allows either local signing of requests using the users
    # own certificate or delegation based signing via a webservice
    #
    # This allows one to integrate the Choria CLI into a centralised authentication, authorization and
    # auditing system
    #
    # Available settings:
    #
    #   choria.security.request_signer.plugin - the plugin to use, `choria` for this one - the default.
    #   choria.security.request_signer.token_file - a file holding a token like a JWT or similar
    #   choria.security.request_signer.token_environment - a ENV key holding a token like a JWT or similar
    #   choria.security.request_signer.url - a endpoint that implements the v1 signer protocol
    #
    # The webservice has to support the specification found at https://choria.io/schemas/choria/signer/v1/service.json
    class Choria < Base
      # Retrieves the token from either a local file or the users environment
      #
      # @return [String, nil]
      def token
        file = @config.pluginconf["choria.security.request_signer.token_file"]
        env = @config.pluginconf["choria.security.request_signer.token_environment"]

        if file
          file = File.expand_path(file)

          unless File.exist?(file)
            raise("No token found in %s, please authenticate using your configured authentication service" % file)
          end

          return File.read(file).chomp
        end

        raise("could not find token in environment variable %s" % env) unless ENV[env]

        ENV[env].chomp
      end

      # Signs the secure request
      #
      # Signing supports either local mode using local certificates or delegating to a remote
      # signer that is written in conformance with the signer specification version 1
      #
      # @param secure_request [Hash] a v1 secure request
      def sign_secure_request!(secure_request)
        return if $choria_unsafe_disable_protocol_security # rubocop:disable Style/GlobalVars

        if remote_signer?
          remote_sign!(secure_request)
        else
          local_sign!(secure_request)
        end
      end

      # Determines the callerid for this client
      #
      # When a remote signer is enabled the caller is extracted from the JWT
      # otherwise a choria=user style ID is generated
      #
      # @return [String]
      # @raise [Exception] when the JWT is invalid
      def callerid
        if remote_signer?
          parts = token.split(".")

          raise("Invalid JWT token") unless parts.length == 3

          claims = JSON.parse(Base64.decode64(parts[1]))

          raise("Invalid JWT token") unless claims.include?("callerid")
          raise("Invalid JWT token") unless claims["callerid"].is_a?(String)
          raise("Invalid JWT token") if claims["callerid"].empty?

          claims["callerid"]
        else
          "choria=%s" % choria.certname
        end
      end

      # The body that would be submitted to the remote service
      #
      # @param secure_request [Hash] a v1 secure request
      # @return [Hash]
      def sign_request_body(secure_request)
        {
          "token" => token,
          "request" => Base64.encode64(secure_request["message"])
        }
      end

      # Performs a remote sign operation against a configured web service
      #
      # @param secure_request [Hash] a v1 secure request
      # @raise [StandardError] on signing error
      def remote_sign!(secure_request)
        Log.info("Signing secure request using remote signer %s" % remote_signer_url)

        uri = remote_signer_url
        post = choria.http_post(uri.request_uri)
        post.body = sign_request_body(secure_request).to_json
        post["Content-type"] = "application/json"

        http = choria.https(:target => uri.host, :port => uri.port)
        http.use_ssl = false if uri.scheme == "http"

        # While this might appear alarming it's expected that the clients
        # in this situation will not have any Choria CA issued certificates
        # and so wish to use a remote signer - the certificate management woes
        # being one of the main reasons for centralised AAA.
        #
        # So there is no realistic way to verify these requests especially in the
        # event that these signers run on private IPs and such as would be typical
        # so while we do this big No No of disabling verify here it really is the
        # only thing that make sense.
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE if http.use_ssl?

        resp = http.request(post)

        signature = {}

        if resp.code == "200"
          signature = JSON.parse(resp.body)
        else
          raise("Could not get remote signature: %s: %s" % [resp.code, resp.body])
        end

        if signature["error"]
          raise("Could not get remote signature: %s" % signature["error"])
        end

        signed_request = JSON.parse(Base64.decode64(signature["secure_request"]))
        signed_request.each do |k, v|
          secure_request[k] = v
        end
      end

      # Signs using local certificates
      #
      # @param secure_request [Hash] a v1 secure request
      # @raise [StandardError] on signing error
      def local_sign!(secure_request)
        Log.info("Signing secure request using local credentials")

        secure_request["signature"] = sign(secure_request["message"])
        secure_request["pubcert"] = File.read(client_public_cert).chomp

        nil
      end

      # (see Security::Choria#sign)
      def sign(string, id=nil)
        security.sign(string, id)
      end

      # (see Security::Choria#client_public_cert)
      def client_public_cert
        security.client_public_cert
      end

      # Determines if a remote signer is configured
      #
      # @return [Boolean]
      def remote_signer?
        !!(remote_signer_url == "" || remote_signer_url)
      end

      # Determines the remote url to submit standard signing requests to
      #
      # @return [URI, Nil]
      def remote_signer_url
        return nil unless @config.pluginconf["choria.security.request_signer.url"]
        return nil if @config.pluginconf["choria.security.request_signer.url"] == ""

        URI.parse(@config.pluginconf["choria.security.request_signer.url"])
      end

      def security
        @security ||= PluginManager["security_plugin"]
      end

      def choria
        @choria ||= security.choria
      end
    end
  end
end

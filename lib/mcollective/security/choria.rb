require "base64"
require "openssl"
require "yaml"

require_relative "../util/choria"

module MCollective
  module Security
    class Choria < Base
      def choria
        @_choria ||= Util::Choria.new("production", nil, false)
      end

      # Encodes a request on behalf of the MCollective Client code
      #
      # The request is turned into a `mcollective:request:3` message and then encoded in
      # a `mcollective::security::choria:request:1` message prior to being serialized
      #
      # @param sender [String] the sender identity, typically @config.identity
      # @param msg [Object] message to be sent, there really is no actual standard to these, any Ruby Object
      # @param requestid [String] a UUID representing the message to be sent
      # @param filter [Hash] the MCollective filter used for routing this request
      # @param target_agent [String] the destination agent name
      # @param target_collective [String] the sub collective to publish this message in
      # @param ttl [Fixnum] how long this message is valid for
      # @return [String] serialized message to be transmitted over the wire
      def encoderequest(sender, msg, requestid, filter, target_agent, target_collective, ttl=60)
        request = empty_request
        request["message"] = msg
        request["envelope"]["requestid"] = requestid
        request["envelope"]["filter"] = filter
        request["envelope"]["agent"] = target_agent
        request["envelope"]["collective"] = target_collective
        request["envelope"]["ttl"] = ttl
        request["envelope"]["callerid"] = callerid

        serialized_request = serialize(request, :yaml)

        serialize(
          "protocol" => "mcollective::security::choria:request:1",
          "message" => serialized_request,
          "signature" => sign(serialized_request),
          "pubcert" => File.read(client_public_cert).chomp
        )
      end

      # Encodes a reply to a earlier received message
      #
      # The reply is turned into a `mcollective:reply:3` and then encoded in
      # a `mcollective::security::choria:reply:1` before being serialized
      #
      # @param sender_agent [String] the agent sending the message
      # @param msg [Object] the message to send
      # @param requestid [String] the requestid the message is a reply to
      # @param requestcallerid [String] the callerid of the requestor
      # @return [String] serialized message to be transmitted over the wire
      def encodereply(sender_agent, msg, requestid, requestcallerid=nil)
        reply = empty_reply
        reply["envelope"]["requestid"] = requestid
        reply["envelope"]["agent"] = sender_agent
        reply["message"] = msg

        serialized_reply = serialize(reply, :yaml)

        serialize(
          "protocol" => "mcollective::security::choria:reply:1",
          "message" => serialized_reply,
          "hash" => hash(serialized_reply)
        )
      end

      # Decodes a message and validates it's security
      #
      # This will delegate the actual checking of messages to {#decode_request} and {#decode_reply}.
      #
      # @see MCollective::Security::Message#decode!
      # @param message [Message] the message holding unverified/validated payload
      # @raise [SecurityValidationFailed] when the message does not pass security checks
      # @return [void]
      def decodemsg(message)
        secure_payload = deserialize(message.payload)

        if secure_payload["protocol"] == "mcollective::security::choria:request:1"
          decode_request(message, secure_payload)

        elsif secure_payload["protocol"] == "mcollective::security::choria:reply:1"
          decode_reply(secure_payload)

        else
          Log.debug("Unknown protocol in message:\n%s" % secure_payload.pretty_inspect)
          raise(SecurityValidationFailed, "Received an unknown protocol '%s' message, ignoring" % secure_payload["protocol"])
        end
      end

      # Validates a received request is in the correct format and passes security checks
      #
      # During this the YAML encoded `message` held will be deserialized
      #
      # @param message [Message]
      # @param secure_payload [Hash] A mcollective::security::choria:request:1 message
      # @raise [SecurityValidationFailed] when the message does not pass security checks
      # @return [Hash] a legacy MCollective request structure, see {#to_legacy_request}
      def decode_request(message, secure_payload)
        request = deserialize(secure_payload["message"], :yaml)

        unless valid_protocol?(request, "mcollective:request:3", empty_request)
          raise(SecurityValidationFailed, "Unknown request body format received. Expected mcollective:request:3, cannot continue")
        end

        cache_client_pubcert(request["envelope"], secure_payload["pubcert"]) if @initiated_by == :node

        validrequest?(secure_payload, request)

        should_process_msg?(message, request["envelope"]["requestid"])

        to_legacy_request(request)
      end

      # Validates a received reply is in the correct format and passes security checks
      #
      # During this the YAML encoded `message` held will be deserialized
      #
      # @note right now no actual security checks are done on replies
      # @param secure_payload [Hash] a mcollective::security::choria:reply:1 message
      # @raise [SecurityValidationFailed] when the message does not pass security checks
      # @return [Hash] a legacy MCollective reply structure, see {#to_legacy_reply}
      def decode_reply(secure_payload)
        reply = deserialize(secure_payload["message"], :yaml)

        unless valid_protocol?(reply, "mcollective:reply:3", empty_reply)
          raise(SecurityValidationFailed, "Unknown reply body format received. Expected mcollective:reply:3, cannot continue")
        end

        to_legacy_reply(reply)
      end

      # Verifies the request by checking it's been signed with the cached certificate of the claimed callerid
      #
      # @param secure_payload [Hash] a mcollective::security::choria:request:1 message
      # @param request [Hash] a mcollective:request:3 message
      # @return [Boolean]
      # @raise [SecurityValidationFailed] when the message cannot be decoded
      def validrequest?(secure_payload, request)
        callerid = request["envelope"]["callerid"]

        if verify_signature(secure_payload["message"], secure_payload["signature"], callerid, true)
          Log.info("Received valid request %s from %s" % [request["envelope"]["requestid"], callerid])
          @stats.validated
        else
          @stats.unvalidated
          raise(SecurityValidationFailed, "Received an invalid signature in message from %s" % callerid)
        end

        true
      end

      # Checks the structure of a message is well formed
      #
      # @todo this really should be json schema or even better protobufs
      # @param body [Hash] a mcollective:request:3 or mcollective:reply:3
      # @param protocol [String] the expected protocol
      # @param template [Hash] a template message to check against {#empty_reply} or {#empty_request}
      # @return [Boolean]
      def valid_protocol?(body, protocol, template)
        unless body.is_a?(Hash)
          Log.warn("Body from the message should be a Hash")
          return false
        end

        unless body["protocol"] == protocol
          Log.warn("Unknown message protocol, should be %s" % protocol)
          return false
        end

        unless body.include?("envelope")
          Log.warn("No envelope found in the message")
          return false
        end

        envelope = body["envelope"]

        unless envelope.is_a?(Hash)
          Log.warn("Envelope in message is not a hash")
          return false
        end

        valid_envelope = template["envelope"].keys

        unless (envelope.keys - valid_envelope).empty?
          Log.warn("Envelope does not have the correct keys, only %s allowed" % valid_envelope.join(", "))
          return false
        end

        unless body.include?("message")
          Log.warn("Body has no message")
          return false
        end

        true
      end

      # Parse a comma seperated list into a Regex spanning the list
      #
      # @param list [String] comma seperated list of strings and regex
      # @param default [String,Regexp] what to do for empty lists
      # @return [Regexp]
      def comma_sep_list_to_regex(list, default)
        matchlist = list.split(",").map do |item|
          item.strip!

          if item =~ /^\/(.+)\/$/
            Regexp.new($1)
          else
            item
          end
        end.compact

        matchlist << default if matchlist.empty?

        Regexp.union(matchlist.compact.uniq)
      end

      # Calculate a Regex that will match the entire privileged user list
      #
      # Defaults to match /\.privileged.mcollective$/ othwerwise whatever is specified,
      # in the comma seperated config item `choria.security.privileged_users`
      #
      # @example specific certs and the default
      #
      #     plugin.choria.security.privileged_users = bob, /\.privileged.mcollective$/
      #
      # @return [Regexp]
      def privilegeduser_regex
        users = @config.pluginconf.fetch("choria.security.privileged_users", "")

        comma_sep_list_to_regex(users, /\.privileged\.mcollective$/)
      end

      # Search the cache directory for certificates matching the privileged user list
      #
      # @return [Array<String>] list of full paths to privileged certs
      def privilegeduser_certs
        match = privilegeduser_regex
        dir = server_public_cert_dir

        certs = Dir.entries(dir).grep(/pem$/).select do |cert|
          File.basename(cert, ".pem").match(match)
        end

        certs.map {|cert| File.join(dir, cert) }
      rescue Errno::ENOENT
        []
      end

      # Calculate a Regex that will match the entire cert whitelist
      #
      # Defaults to match /\.mcollective$/ othwerwise whatever is specified,
      # in the comma seperated config item `choria.security.cert_whitelist`
      #
      # @example specific certs and the default
      #
      #     plugin.choria.security.certname_whitelist = bob,/\.mcollective$/
      #
      # @return [Regexp]
      def certname_whitelist_regex
        whitelist = @config.pluginconf.fetch("choria.security.certname_whitelist", "")

        comma_sep_list_to_regex(whitelist, /\.mcollective$/)
      end

      # Determines if a certificate should be cached
      #
      # This checks the cert is valid against our CA, it's name etc
      #
      # @todo support white/black lists
      # @param pubcert [String] PEM encoded X509 cert text
      # @param callerid [String] callerid who sent this cert
      # @return [Boolean]
      def should_cache_certname?(pubcert, callerid)
        certname = valid_certificate?(pubcert)
        callerid_certname = certname_from_callerid(callerid)
        valid_regex = certname_whitelist_regex

        unless certname
          Log.warn("Received a certificate for '%s' that is not signed by a known CA, discarding" % callerid_certname)
          return false
        end

        # this cert is allowed to set callerids != certname, so check it here and log callerid
        if certname =~ privilegeduser_regex
          Log.warn("Allowing cache of privileged user certname %s from callerid %s" % [certname, callerid])
          return true
        end

        unless certname == callerid_certname
          Log.warn("Received a certificate called '%s' that does not match the received callerid of '%s'" % [certname, callerid_certname])
          return false
        end

        unless certname =~ valid_regex
          Log.warn("Received certificate name '%s' does not match %s" % [certname, valid_regex])
          return false
        end

        true
      end

      def parse_pubcert(pubcert)
        OpenSSL::X509::Certificate.new(pubcert)
      rescue OpenSSL::X509::CertificateError
        Log.warn("Received certificate is not a valid x509 certificate: %s: %s" % [$!.class, $!.to_s])
        false
      end

      # Metadata about a pubcert based on the envelope
      #
      # @param envelope [Hash] the envelope from a mcollective:request:3
      # @param pubcert [String] PEM encoded X509 public certificate
      # @return [Hash]
      def client_pubcert_metadata(envelope, pubcert)
        cert = parse_pubcert(pubcert)

        {
          "create_time" => current_timestamp,
          "senderid" => envelope["senderid"],
          "requestid" => envelope["requestid"],
          "certinfo" => {
            "issuer" => cert.issuer.to_s,
            "not_after" => Integer(cert.not_after),
            "not_before" => Integer(cert.not_before),
            "serial" => cert.serial.to_s,
            "subject" => cert.subject.to_s,
            "version" => cert.version,
            "signature_algorithm" => cert.signature_algorithm
          }
        }
      end

      # Mutex used for locking write access to the pubcert cache
      #
      # @return [Mutex]
      def client_cache_mutex
        @_ccmutex ||= Mutex.new
      end

      # Caches the public certificate of a sender
      #
      # If there is not yet a cached certificate for the callerid a new one
      # is saved after first checking it against our CA
      #
      # @param envelope [Hash] the envelope from a mcollective:request:3
      # @param pubcert [String] a X509 public certificate in PEM format
      # @return [Boolean] true when the cert was cached, false when already cached
      # @raise [StandardError] when an invalid cert was received
      def cache_client_pubcert(envelope, pubcert)
        client_cache_mutex.synchronize do
          callerid = envelope["callerid"]
          certfile = public_certfile(callerid)
          certmetadata = public_cert_metadatafile(callerid)

          if !File.exist?(certfile)
            unless should_cache_certname?(pubcert, callerid)
              raise("Received an invalid certificate for %s" % callerid)
            end

            Log.info("Saving verified pubcert for %s in %s" % [callerid, certfile])

            File.open(certfile, "w") do |f|
              f.print(pubcert)
            end

            File.open(certmetadata, "w") do |f|
              f.print(client_pubcert_metadata(envelope, pubcert).to_json)
            end

            true
          else
            Log.debug("Already have a cert from %s in %s" % [callerid, certfile])

            false
          end
        end
      end

      # Validates a certificate against the CA
      #
      # @param pubcert [String] PEM encoded X509 public certificate
      # @return [String,false] when succesful, the certname else false
      # @raise [Exception] in case OpenSSL fails to open the various certificates
      def valid_certificate?(pubcert)
        unless File.readable?(ca_path)
          raise("Cannot find or read the CA in %s, cannot verify public certificate" % ca_path)
        end

        incoming = parse_pubcert(pubcert)

        return false unless incoming

        begin
          ca = OpenSSL::X509::Certificate.new(File.read(ca_path))
        rescue OpenSSL::X509::CertificateError
          Log.warn("Failed to load CA from %s: %s: %s" % [ca_path, $!.class, $!.to_s])
          raise
        end

        unless incoming.issuer.to_s == ca.subject.to_s && incoming.verify(ca.public_key)
          Log.warn("Failed to verify certificate %s against CA %s in %s" % [incoming.subject.to_s, ca.subject.to_s, ca_path])
          return false
        end

        Log.info("Verified certificate %s against CA %s" % [incoming.subject.to_s, ca.subject.to_s])

        incoming.subject.to_a.first[1]
      end

      # Determines the path to a cached certificate for a caller
      #
      # @param callerid [String] the callerid to find a cert for
      # @return [String] path to the pem file
      def public_certfile(callerid)
        "%s/%s.pem" % [server_public_cert_dir, certname_from_callerid(callerid)]
      end

      def public_cert_metadatafile(callerid)
        public_certfile(callerid).gsub(/\.pem$/, ".json")
      end

      # Parses our callerids and return the certname
      #
      # @param id [String] the callerid to parse
      # @return [String] the certificate name
      # @raise [StandardError] when a unexpected format id is received
      def certname_from_callerid(id)
        if id =~ /^choria=([\w\.\-]+)/
          $1
        else
          raise("Received a callerid in an unexpected format: %s" % id)
        end
      end

      # Serialize a object
      #
      # @param obj [Object] the item to serialize
      # @param format [:json, :yaml] the serializer to use
      # @return [String]
      def serialize(obj, format=:json)
        if format == :yaml
          YAML.dump(obj)
        else
          JSON.dump(obj)
        end
      end

      # Deserialize a string
      #
      # @param string [String] the serialized text
      # @param format [:json, :yaml] the serializer to use
      # @return [Class]
      def deserialize(string, format=:json)
        if format == :yaml
          YAML.load(string)
        else
          JSON.parse(string)
        end
      end

      # The path where a server caches client certificates
      #
      # @note when the path does not exist it will attempt to make it
      # @return [String]
      # @raise [StandardError] when creating the directory fails
      def server_public_cert_dir
        if Util.windows?
          dir = File.join(Util.windows_prefix, "choria_security", "public_certs")
        else
          dir = "/etc/puppetlabs/mcollective/choria_security/public_certs"
        end

        FileUtils.mkdir_p(dir) unless File.directory?(dir)

        dir
      end

      # (see Util::Choria#ca_path)
      def ca_path
        choria.ca_path
      end

      # (see Util::Choria#ssl_dir)
      def ssl_dir
        choria.ssl_dir
      end

      # (see Util::Choria#certname)
      def certname
        choria.certname
      end

      def env_fetch(key, default=nil)
        choria.env_fetch(key, default)
      end

      # (see Util::Choria#client_public_cert)
      def client_public_cert
        choria.client_public_cert
      end

      # (see Util::Choria#client_private_key)
      def client_private_key
        choria.client_private_key
      end

      # The callerid based on the certificate name
      #
      # Caller ids are in the form `choria=certname`
      #
      # @return [String] callerid
      def callerid
        "choria=%s" % certname
      end

      # Signs a string using the private key
      #
      # @param string [String] the string to sign
      # @param id [String] a callerid to sign as
      # @return [String] Base64 encoded signature
      # @raise [Exception] in case OpenSSL fails for some reason or keys cannot be found
      def sign(string, id=nil)
        key = client_private_key

        if File.readable?(key)
          Log.debug("Signing request using client private key %s" % key)
        else
          raise("Cannot find private key %s, cannot sign message" % key)
        end

        key = OpenSSL::PKey::RSA.new(File.read(key))
        signed = key.sign(OpenSSL::Digest::SHA256.new, string)

        Base64.encode64(signed).chomp
      end

      # Verifies a signature of a string using a certificate
      #
      # Optionally should the signature validation fail - or the specified cert does not exist -
      # the list of privileged user certs will be tried to validate the message and any of those can
      # validate it
      #
      # @param string [String] the signed string
      # @param signature [String] Base64 encoded signature to verify
      # @param callerid [String] Callerid to verify the signature for
      # @param allow_privileged [Boolean] when true will check the privileged user certs should the main cert fails
      def verify_signature(string, signature, callerid, allow_privileged=false)
        candidate_keys = [public_certfile(callerid)]

        candidate_keys.concat(privilegeduser_certs) if allow_privileged

        candidate_keys.each do |certname|
          next unless File.exist?(certname)

          key = OpenSSL::X509::Certificate.new(File.read(certname)).public_key
          result = key.verify(OpenSSL::Digest::SHA256.new, Base64.decode64(signature), string)

          if result
            Log.debug("Message validated using certificate in %s (allow_privileged=%s)" % [certname, allow_privileged])
            return true
          end
        end

        false
      end

      # Produce a Base64 encoded SHA256 digest of a string
      #
      # @param string [String] the string to hash
      # @return [String]
      def hash(string)
        OpenSSL::Digest.new("sha256", string).to_s
      end

      # Retrieves the current time in UTC
      #
      # @return [Fixnum] seconds since epoch
      def current_timestamp
        Integer(Time.now.utc)
      end

      # Creates a empty mcollective:request:3
      #
      # Some envelope fields like time are set to sane defautls
      #
      # @return [Hash]
      def empty_request
        {
          "protocol" => "mcollective:request:3",
          "message" => nil,
          "envelope" => {
            "requestid" => nil,
            "senderid" => @config.identity,
            "callerid" => nil,
            "filter" => {},
            "collective" => @config.main_collective,
            "agent" => nil,
            "ttl" => @config.ttl,
            "time" => current_timestamp
          }
        }
      end

      # Creates a empty mcollective:reply:3
      #
      # Some envelope fields like time are set to sane defautls
      #
      # @return [Hash]
      def empty_reply
        {
          "protocol" => "mcollective:reply:3",
          "message" => nil,
          "envelope" => {
            "senderid" => @config.identity,
            "requestid" => nil,
            "agent" => nil,
            "time" => current_timestamp
          }
        }
      end

      # Converts a mcollective:request:3 to a legacy format
      #
      # @return [Hash]
      def to_legacy_request(body)
        {
          :body => body["message"],
          :senderid => body["envelope"]["senderid"],
          :requestid => body["envelope"]["requestid"],
          :filter => body["envelope"]["filter"],
          :collective => body["envelope"]["collective"],
          :agent => body["envelope"]["agent"],
          :callerid => body["envelope"]["callerid"],
          :ttl => body["envelope"]["ttl"],
          :msgtime => body["envelope"]["time"]
        }
      end

      # Converts a mcollective:reply:3 to a legacy format
      #
      # @return [Hash]
      def to_legacy_reply(body)
        {
          :senderid => body["envelope"]["senderid"],
          :requestid => body["envelope"]["requestid"],
          :senderagent => body["envelope"]["agent"],
          :msgtime => body["envelope"]["time"],
          :body => body["message"]
        }
      end
    end
  end
end

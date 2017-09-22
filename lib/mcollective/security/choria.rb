require "base64"
require "openssl"
require "yaml"

require_relative "../util/choria"

module MCollective
  module Security
    class Choria < Base
      def initialize
        super

        # Stores lists of requests that came from legacy choria clients so they
        # can be encoded appropriately for them on reply
        #
        # This has to be an expiring entity since not all requests make
        # replies
        #
        # See issue 288 for background on this, this can be removed once we hit
        # 1.0.0 along with the calls to the methods using this
        Cache.setup(:choria_security, 3600)
      end

      def choria
        @_choria ||= Util::Choria.new(false)
      end

      # Encodes a request on behalf of the MCollective Client code
      #
      # The request is turned into a `choria:request:1` message and then encoded in
      # a `choria:secure:request:1` message prior to being serialized
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
        request["message"] = serialize(msg, default_serializer)
        request["envelope"]["requestid"] = requestid
        request["envelope"]["filter"] = filter
        request["envelope"]["agent"] = target_agent
        request["envelope"]["collective"] = target_collective
        request["envelope"]["ttl"] = ttl
        request["envelope"]["callerid"] = callerid

        serialized_request = serialize(request, default_serializer)

        serialize(
          "protocol" => "choria:secure:request:1",
          "message" => serialized_request,
          "signature" => sign(serialized_request),
          "pubcert" => File.read(client_public_cert).chomp
        )
      end

      # Encodes a reply to a earlier received message
      #
      # The reply is turned into a `choria:reply:1` and then encoded in
      # a `choria:secure:reply:1` before being serialized
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

        if legacy_request?(requestid)
          reply["message"] = msg
          legacy_processed!(requestid)
        else
          reply["message"] = serialize(msg, default_serializer)
        end

        serialized_reply = serialize(reply, default_serializer)

        serialize(
          "protocol" => "choria:secure:reply:1",
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

        if secure_payload["protocol"] == "choria:secure:request:1"
          decode_request(message, secure_payload)

        elsif secure_payload["protocol"] == "choria:secure:reply:1"
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
      # @param secure_payload [Hash] A choria:secure:request:1 message
      # @raise [SecurityValidationFailed] when the message does not pass security checks
      # @return [Hash] a legacy MCollective request structure, see {#to_legacy_request}
      def decode_request(message, secure_payload)
        request = deserialize(secure_payload["message"], default_serializer)

        unless valid_protocol?(request, "choria:request:1", empty_request) || valid_protocol?(request, "mcollective:request:3", empty_request)
          raise(SecurityValidationFailed, "Unknown request body format received. Expected choria:request:1 or mcollective:request:3, cannot continue")
        end

        cache_client_pubcert(request["envelope"], secure_payload["pubcert"]) if @initiated_by == :node

        validrequest?(secure_payload, request)

        should_process_msg?(message, request["envelope"]["requestid"])

        if request["message"].is_a?(String)
          # non json based things like 'mco ping' that just sends 'ping' will fail on JSON serialize
          # while yaml would not fail and just return the string
          #
          # So we ensure the message is left as it was should json deserialize fail, tbh this a train wreck
          # but it's how the original mcollective was designed, definitely need a bit of a rethink there as
          # at core its not compatible with this JSON stuff as is
          begin
            request["message"] = deserialize(request["message"], default_serializer)
          rescue # rubocop:disable Lint/HandleExceptions
          end
        else
          record_legacy_request(request)
        end

        to_legacy_request(request)
      end

      # Records the fact that a request is from a legacy client
      #
      # @param request [Hash] decoded request
      def record_legacy_request(request)
        if request["envelope"] && request["envelope"]["requestid"]
          Cache.write(:choria_security, request["envelope"]["requestid"], true)
        end
      end

      # Determines if a specific requestid was a previously seen legacy request
      #
      # @param requestid [String]
      # @return [Boolean]
      def legacy_request?(requestid)
        !!Cache.read(:choria_security, requestid)
      rescue
        false
      end

      # Mark a request as processed and mark it for removal from the cache
      #
      # @param requestid [String]
      def legacy_processed!(requestid)
        Cache.invalidate!(:choria_security, requestid)
      end

      # Validates a received reply is in the correct format and passes security checks
      #
      # During this the YAML encoded `message` held will be deserialized
      #
      # @note right now no actual security checks are done on replies
      # @param secure_payload [Hash] a choria:secure:reply:1 message
      # @raise [SecurityValidationFailed] when the message does not pass security checks
      # @return [Hash] a legacy MCollective reply structure, see {#to_legacy_reply}
      def decode_reply(secure_payload)
        reply = deserialize(secure_payload["message"], default_serializer)

        if reply["message"].is_a?(String)
          # non json based things like 'mco ping' that just sends 'ping' will fail on JSON serialize
          # while yaml would not fail and just return the string
          #
          # So we ensure the message is left as it was should json deserialize fail, tbh this a train wreck
          # but it's how the original mcollective was designed, definitely need a bit of a rethink there as
          # at core its not compatible with this JSON stuff as is
          begin
            reply["message"] = deserialize(reply["message"], default_serializer)
          rescue # rubocop:disable Lint/HandleExceptions
          end
        end

        unless valid_protocol?(reply, "choria:reply:1", empty_reply) || valid_protocol?(reply, "mcollective:reply:3", empty_reply)
          raise(SecurityValidationFailed, "Unknown reply body format received. Expected choria:reply:1 or mcollective:reply:3, cannot continue")
        end

        to_legacy_reply(reply)
      end

      # Verifies the request by checking it's been signed with the cached certificate of the claimed callerid
      #
      # @param secure_payload [Hash] a choria:secure:request:1 message
      # @param request [Hash] a choria:request:1 message
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
      # @param body [Hash] a choria:request:1 or choria:reply:1
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
        certname = choria.valid_certificate?(pubcert)
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

      # Metadata about a pubcert based on the envelope
      #
      # @param envelope [Hash] the envelope from a choria:request:1
      # @param pubcert [String] PEM encoded X509 public certificate
      # @return [Hash]
      def client_pubcert_metadata(envelope, pubcert)
        cert = choria.parse_pubcert(pubcert)

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
      # @param envelope [Hash] the envelope from a choria:request:1
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

      # Determines the default serializer
      #
      # As of MCollective 2.11.0 it will translate "package" into :package to
      # faciliate JSON requests and other programming languages.  This is a super
      # experimental feature but will allow us to ditch YAML for now.
      #
      # By setting `choria.security.serializer` to JSON this new behaviour can be
      # tested
      #
      # @return [Symbol]
      def default_serializer
        @config.pluginconf.fetch("choria.security.serializer", "yaml").downcase.intern
      end

      # The path where a server caches client certificates
      #
      # @note when the path does not exist it will attempt to make it
      # @return [String]
      # @raise [StandardError] when creating the directory fails
      def server_public_cert_dir
        dir = File.join(ssl_dir, "choria_security", "public_certs")

        FileUtils.mkdir_p(dir) unless File.directory?(dir)

        dir
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
        OpenSSL::Digest.new("sha256", string).base64digest
      end

      # Retrieves the current time in UTC
      #
      # @return [Fixnum] seconds since epoch
      def current_timestamp
        Integer(Time.now.utc)
      end

      # Creates a empty choria:request:1
      #
      # Some envelope fields like time are set to sane defautls
      #
      # @return [Hash]
      def empty_request
        {
          "protocol" => "choria:request:1",
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

      # Creates a empty choria:reply:1
      #
      # Some envelope fields like time are set to sane defautls
      #
      # @return [Hash]
      def empty_reply
        {
          "protocol" => "choria:reply:1",
          "message" => nil,
          "envelope" => {
            "senderid" => @config.identity,
            "requestid" => nil,
            "agent" => nil,
            "time" => current_timestamp
          }
        }
      end

      # Converts a choria filter into a legacy format
      #
      # Choria filters have strings for fact filter keys, mcollective expect symbols
      #
      # @param filter [Hash] the input filter
      # @return [Hash] a new filter converted to legacy format
      def to_legacy_filter(filter)
        return filter unless filter.include?("fact")

        new = {}

        filter.each do |key, value|
          new[key] = value

          next unless key == "fact"

          new["fact"] = value.map do |ff|
            {
              :fact => ff.fetch(:fact, ff["fact"]),
              :operator => ff.fetch(:operator, ff["operator"]),
              :value => ff.fetch(:value, ff["value"])
            }
          end
        end

        new
      end

      # Converts a choria:request:1 to a legacy format
      #
      # @return [Hash]
      def to_legacy_request(body)
        {
          :body => body["message"],
          :senderid => body["envelope"]["senderid"],
          :requestid => body["envelope"]["requestid"],
          :filter => to_legacy_filter(body["envelope"]["filter"]),
          :collective => body["envelope"]["collective"],
          :agent => body["envelope"]["agent"],
          :callerid => body["envelope"]["callerid"],
          :ttl => body["envelope"]["ttl"],
          :msgtime => body["envelope"]["time"]
        }
      end

      # Converts a choria:reply:1 to a legacy format
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

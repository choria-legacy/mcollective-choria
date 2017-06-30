require "spec_helper"

require "mcollective/security/choria"

module MCollective
  describe Security::Choria do
    let(:security) { Security::Choria.new }
    let(:choria) { security.choria }

    before(:each) do
      security.stubs(:current_timestamp).returns(1464002319)
      RSpec.configuration.json_schemas["choria:secure:request:1"] = "schemas/choria_secure_request_1.json"
      RSpec.configuration.json_schemas["choria:secure:reply:1"] = "schemas/choria_secure_reply_1.json"
    end

    describe "#default_serializer" do
      it "should default to yaml" do
        expect(security.default_serializer).to be(:yaml)
      end

      it "should support JSON" do
        Config.instance.expects(:pluginconf).returns(
          "choria.security.serializer" => "JSON"
        )

        expect(security.default_serializer).to be(:json)
      end
    end

    describe "#client_pubcert_metadata" do
      it "should return correct metadata" do
        envelope = security.empty_request["envelope"]
        envelope["requestid"] = "rspec.request"
        envelope["senderid"] = "rspec.sender"

        security.stubs(:current_timestamp).returns(time = Time.now.utc.to_i)

        expect(security.client_pubcert_metadata(envelope, File.read("spec/fixtures/rip.mcollective.pem"))).to eq(
          "create_time" => time,
          "requestid" => "rspec.request",
          "senderid" => "rspec.sender",
          "certinfo" => {
            "issuer" => "/CN=Puppet CA: dev2.devco.net",
            "not_after" => 1621361958,
            "not_before" => 1463595558,
            "serial" => "4",
            "subject" => "/CN=rip.mcollective",
            "version" => 2,
            "signature_algorithm" => "sha256WithRSAEncryption"
          }
        )
      end
    end

    describe "#privilegeduser_certs" do
      it "should return a valid list" do
        security.stubs(:server_public_cert_dir).returns("/etc/puppetlabs/mcollective/choria_security/public_certs")
        Dir.expects(:entries).with("/etc/puppetlabs/mcollective/choria_security/public_certs").returns([".", "..", "rip.mcollective.pem", "x.privileged.mcollective.pem"])

        expect(security.privilegeduser_certs).to eq(["/etc/puppetlabs/mcollective/choria_security/public_certs/x.privileged.mcollective.pem"])
      end
    end

    describe "#privilegeduser_regex" do
      it "should have a sane default" do
        expect(security.privilegeduser_regex).to eq(/\.privileged\.mcollective$/)
      end

      it "should allow a configurable list" do
        Config.instance.expects(:pluginconf).returns(
          "choria.security.privileged_users" => "bob , /\.mcollective$/"
        )

        expect(security.privilegeduser_regex).to eq(/bob|(?-mix:.mcollective$)/)
      end
    end

    describe "#certname_whitelist_regex" do
      it "should have a sane default" do
        expect(security.certname_whitelist_regex).to eq(/\.mcollective$/)
      end

      it "should allow a configurable list" do
        Config.instance.expects(:pluginconf).returns(
          "choria.security.certname_whitelist" => "bob , /\.mcollective$/"
        )

        expect(security.certname_whitelist_regex).to eq(/bob|(?-mix:.mcollective$)/)
      end
    end

    describe "#encoderequest" do
      it "should produce a valid choria:secure:request:1" do
        security.initiated_by = :client
        security.stubs(:client_private_key).returns("spec/fixtures/rip.mcollective.key")
        security.stubs(:client_public_cert).returns("spec/fixtures/rip.mcollective.pem")
        security.stubs(:callerid).returns("choria=rip.mcollective")
        encoded = security.encoderequest("some.node", "rspec message", "requestid", [], "rspec_agent", "mcollective", 120)

        request = JSON.parse(encoded)
        message = YAML.load(request["message"])

        expect(encoded).to match_json_schema("choria:secure:request:1")
        expect(request["signature"]).to match(/^r9F3fuTEv43JYzZJ6.+cHRWGmz0mxZmy5Us1xR2.+CMYUlTJIFfqNa4OEURpFybE=$/m)
        expect(request["pubcert"]).to match(File.read("spec/fixtures/rip.mcollective.pem").chomp)
        expect(message).to eq(
          "protocol" => "choria:request:1",
          "message" => YAML.dump("rspec message"),
          "envelope" =>
          {"requestid" => "requestid",
           "senderid" => "rspec_identity",
           "callerid" => "choria=rip.mcollective",
           "filter" => [],
           "collective" => "mcollective",
           "agent" => "rspec_agent",
           "ttl" => 120,
           "time" => 1464002319}
        )
      end
    end

    describe "#encodereply" do
      it "should produce a valid choria:secure:reply:1" do
        encoded = security.encodereply("rspec_agent", "rspec message", "123")

        reply = JSON.parse(encoded)
        message = YAML.load(reply["message"])

        expect(encoded).to match_json_schema("choria:secure:reply:1")
        expect(message).to eq(
          "protocol" => "choria:reply:1",
          "message" => YAML.dump("rspec message"),
          "envelope" =>
          {"senderid" => "rspec_identity",
           "requestid" => "123",
           "agent" => "rspec_agent",
           "time" => 1464002319}
        )
      end

      it "should support previously seen legacy messages" do
        security.record_legacy_request("envelope" => {"requestid" => "123"})
        expect(security.legacy_request?("123")).to be(true)
        encoded = security.encodereply("rspec_agent", "rspec message", "123")
        expect(security.legacy_request?("123")).to be(false)

        reply = JSON.parse(encoded)
        message = YAML.load(reply["message"])
        expect(message["message"]).to eq("rspec message")
      end
    end

    describe "#decodemsg" do
      it "should decode requests" do
        payload = {
          "protocol" => "choria:secure:request:1",
          "message" => security.serialize(security.empty_request),
          "hash" => security.hash(security.serialize(security.empty_request))
        }

        secure_payload = security.serialize(payload)
        message = stub(:payload => secure_payload)
        security.expects(:decode_request).with(message, payload)
        security.decodemsg(message)
      end

      it "should decode replies" do
        payload = {
          "protocol" => "choria:secure:reply:1",
          "message" => security.serialize(security.empty_reply),
          "hash" => security.hash(security.serialize(security.empty_reply))
        }

        secure_payload = security.serialize(payload)
        message = stub(:payload => secure_payload)
        security.expects(:decode_reply).with(payload)
        security.decodemsg(message)
      end
    end

    describe "#decode_request" do
      let(:request) { security.empty_request }
      let(:requestid) { SSL.uuid.delete("-") }

      before(:each) do
        request["envelope"]["requestid"] = requestid
      end

      it "should fail for invalid protocol messages" do
        security.expects(:valid_protocol?).with({}, "choria:request:1", security.empty_request).returns(false)
        security.expects(:valid_protocol?).with({}, "mcollective:request:3", security.empty_request).returns(false)

        expect {
          security.decode_request({}, "message" => {}.to_yaml)
        }.to raise_error("Unknown request body format received. Expected choria:request:1 or mcollective:request:3, cannot continue")
      end

      it "should return a valid legacy message" do
        message = stub
        secure = {
          "message" => security.serialize(request, :yaml),
          "pubcert" => "rspec_pubcert"
        }

        security.initiated_by = :node
        security.expects(:cache_client_pubcert).with(request["envelope"], secure["pubcert"])
        security.expects(:validrequest?).with(secure, request)
        security.expects(:should_process_msg?).with(message, request["envelope"]["requestid"])

        security.decode_request(message, secure)
      end

      it "should support serialized message bodies" do
        [:json, :yaml].each do |serializer|
          ["ping", {"rspec" => "message"}].each do |body|
            security.stubs(:default_serializer).returns(serializer)
            request["message"] = security.serialize(body, serializer)

            message = stub
            secure = {
              "message" => security.serialize(request, serializer),
              "pubcert" => "rspec_pubcert"
            }

            security.initiated_by = :node
            security.expects(:cache_client_pubcert).with(request["envelope"], secure["pubcert"])
            security.expects(:validrequest?).with(secure, request)
            security.expects(:should_process_msg?).with(message, request["envelope"]["requestid"])

            result = security.decode_request(message, secure)

            expect(result[:body]).to eq(body)
            expect(security.legacy_request?(requestid)).to be(false)
          end
        end
      end

      it "should support unserialized messages" do
        request["message"] = {"rspec" => "message"}

        message = stub
        secure = {
          "message" => security.serialize(request, :yaml),
          "pubcert" => "rspec_pubcert"
        }

        security.initiated_by = :node
        security.expects(:cache_client_pubcert).with(request["envelope"], secure["pubcert"])
        security.expects(:validrequest?).with(secure, request)
        security.expects(:should_process_msg?).with(message, request["envelope"]["requestid"])

        result = security.decode_request(message, secure)

        expect(result[:body]).to eq("rspec" => "message")
        expect(security.legacy_request?(requestid)).to be(true)
      end
    end

    describe "#decode_reply" do
      let(:reply) { security.empty_reply }

      it "should return a valid legacy message" do
        serialized_reply = security.serialize(reply, :yaml)

        message = {
          "protocol" => "mcollective::security::puppet:reply:1",
          "message" => serialized_reply,
          "hash" => security.hash(serialized_reply)
        }

        security.expects(:to_legacy_reply).with(reply).returns("rspec" => 1)
        expect(security.decode_reply(message)).to eq("rspec" => 1)
      end

      it "should fail for invalid protocol messages" do
        security.expects(:valid_protocol?).with({}, "mcollective:reply:3", security.empty_reply).returns(false)
        security.expects(:valid_protocol?).with({}, "choria:reply:1", security.empty_reply).returns(false)

        expect {
          security.decode_reply("message" => {}.to_yaml)
        }.to raise_error("Unknown reply body format received. Expected choria:reply:1 or mcollective:reply:3, cannot continue")
      end

      it "should support serialized message bodies" do
        [:yaml, :json].each do |serializer|
          security.stubs(:default_serializer).returns(serializer)

          reply["message"] = security.serialize({"rspec" => "reply"}, serializer)
          serialized_reply = security.serialize(reply, serializer)

          message = {
            "protocol" => "choria:secure:reply:1",
            "message" => serialized_reply,
            "hash" => security.hash(serialized_reply)
          }

          result = security.decode_reply(message)
          expect(result[:body]).to eq("rspec" => "reply")
        end
      end

      it "should support unserialized messages" do
        security.stubs(:default_serializer).returns(:yaml)
        reply["message"] = {"rspec" => "reply"}

        serialized_reply = security.serialize(reply, :yaml)

        message = {
          "protocol" => "mcollective::security::puppet:reply:1",
          "message" => serialized_reply,
          "hash" => security.hash(serialized_reply)
        }

        result = security.decode_reply(message)
        expect(result[:body]).to eq("rspec" => "reply")
      end
    end

    describe "#validrequest?" do
      let(:request) { security.empty_request }

      it "should fail on invalid signatures" do
        request["envelope"]["callerid"] = "choria=rspec"

        secure = {
          "message" => security.serialize(request, :yaml),
          "signature" => :invalid
        }

        security.expects(:verify_signature).with(secure["message"], secure["signature"], "choria=rspec", true).returns(false)
        security.stats.expects(:unvalidated)

        expect {
          security.validrequest?(secure, request)
        }.to raise_error("Received an invalid signature in message from choria=rspec")
      end

      it "should pass valid certs" do
        security.expects(:verify_signature).returns(true)

        request["envelope"]["callerid"] = "choria=rspec"

        secure = {
          "message" => security.serialize(request, :yaml),
          "signature" => :invalid
        }

        security.stats.expects(:validated)

        expect(security.validrequest?(secure, request)).to be_truthy
      end
    end

    describe "#should_cache_certname?" do
      it "should not allow unvalidated certs" do
        choria.expects(:valid_certificate?).with("x").returns(false)
        Log.expects(:warn).with("Received a certificate for 'rspec' that is not signed by a known CA, discarding")
        expect(security.should_cache_certname?("x", "choria=rspec")).to be_falsey
      end

      it "should allow callers to cache only their own certs" do
        choria.expects(:valid_certificate?).with("x").returns("bob")
        Log.expects(:warn).with("Received a certificate called 'bob' that does not match the received callerid of 'rspec'")
        expect(security.should_cache_certname?("x", "choria=rspec")).to be_falsey
      end

      it "should reject certnames based on a whitelist" do
        choria.stubs(:valid_certificate?).returns("rspec")
        security.stubs(:certname_whitelist_regex).returns(/\.rspec$/)
        Log.expects(:warn).with("Received certificate name 'rspec' does not match (?-mix:\\.rspec$)")
        expect(security.should_cache_certname?("x", "choria=rspec")).to be_falsey
      end

      it "should accept certnames based on a whitelist" do
        choria.stubs(:valid_certificate?).returns("x.rspec")
        security.stubs(:certname_whitelist_regex).returns(/\.rspec$/)
        expect(security.should_cache_certname?("rspec", "choria=x.rspec")).to be_truthy
      end

      it "should allow a privileged user certname regardless of callerid" do
        choria.stubs(:valid_certificate?).returns("rest_server2.privileged.mcollective")
        expect(security.should_cache_certname?("rspec", "choria=x.rspec")).to be_truthy
        expect(security.should_cache_certname?("rspec", "choria=rest_server1")).to be_truthy
      end

      it "should only allow the privileged user cert to override callerids" do
        choria.stubs(:valid_certificate?).returns("bob.mcollective")
        choria.expects(:valid_certificate?).with("rest_server2.privileged.mcollective").never
        security.stubs(:privilegeduser_certs).returns(["rest_server2.privileged.mcollective"])
        expect(security.should_cache_certname?("rspec", "choria=x.rspec")).to be_falsey
      end

      it "should still allow non privileged user certs when a privileged user is defined" do
        security.stubs(:privilegeduser_certs).returns(["root"])
        choria.stubs(:valid_certificate?).returns("rspec.mcollective")
        expect(security.should_cache_certname?("rspec", "choria=rspec.mcollective")).to be_truthy
      end
    end

    describe "#cache_client_pubcert" do
      it "should save valid, unknown certs" do
        pubcert = File.read("spec/fixtures/rip.mcollective.pem")
        File.expects(:open).with("/nonexisting/rip.mcollective.pem", "w")
        File.expects(:open).with("/nonexisting/rip.mcollective.json", "w")
        security.stubs(:public_certfile).returns("/nonexisting/rip.mcollective.pem")
        security.expects(:should_cache_certname?).with(pubcert, "choria=rip.mcollective").returns(true)
        expect(security.cache_client_pubcert({"callerid" => "choria=rip.mcollective"}, pubcert)).to be_truthy
      end

      it "should not save invalid certs" do
        security.stubs(:public_certfile).returns("/nonexisting/rip.mcollective.pem")
        security.expects(:should_cache_certname?).returns(false)

        expect {
          security.cache_client_pubcert({"callerid" => "choria=rip.mcollective"}, "")
        }.to raise_error("Received an invalid certificate for choria=rip.mcollective")
      end

      it "should be a noop otherwise" do
        security.stubs(:public_certfile).returns("spec/fixtures/rip.mcollective.pem")
        expect(security.cache_client_pubcert({"callerid" => "choria=rip.mcollective"}, "x")).to be_falsey
      end
    end

    describe "#certname_from_callerid" do
      it "should fail for invalid ids" do
        expect { security.certname_from_callerid("x") }.to raise_error("Received a callerid in an unexpected format: x")
      end

      it "should parse valid ids" do
        expect(security.certname_from_callerid("choria=rspec")).to eq("rspec")
      end
    end

    describe "#serialize" do
      let(:d) { security.empty_request }

      it "should default to json" do
        expect(security.serialize(d)).to eq(d.to_json)
      end

      it "should support yaml" do
        expect(security.serialize(d, :yaml)).to eq(d.to_yaml)
      end
    end

    describe "#deserialize" do
      let(:d) { security.empty_request }

      it "should default to json" do
        expect(security.deserialize(d.to_json)).to eq(d)
      end

      it "should support yaml" do
        expect(security.deserialize(d.to_yaml, :yaml)).to eq(d)
      end

      it "should uderstand serialized data" do
        expect(security.deserialize(security.serialize(d))).to eq(d)
        expect(security.deserialize(security.serialize(d, :yaml), :yaml)).to eq(d)
      end
    end

    describe "#server_public_cert_dir" do
      before(:each) do
        security.stubs(:ssl_dir).returns("/nonexisting")
      end

      it "should attempt to make it if it doesnt exist" do
        File.expects(:directory?).with("/nonexisting/choria_security/public_certs").returns(false)
        FileUtils.expects(:mkdir_p).with("/nonexisting/choria_security/public_certs")
        expect(security.server_public_cert_dir).to eq("/nonexisting/choria_security/public_certs")
      end

      it "should not make it if it exists" do
        File.expects(:directory?).with("/nonexisting/choria_security/public_certs").returns(true)
        FileUtils.expects(:mkdir_p).never
        expect(security.server_public_cert_dir).to eq("/nonexisting/choria_security/public_certs")
      end
    end

    describe "#callerid" do
      it "should return the correct callerid" do
        security.stubs(:certname).returns("rspec_certname.mcollective")
        expect(security.callerid).to eq("choria=rspec_certname.mcollective")
      end
    end

    describe "#sign" do
      it "should produce correct client signatures" do
        signed = File.read("spec/fixtures/too_many_secrets.sig")
        security.initiated_by = :client
        security.expects(:client_private_key).returns("spec/fixtures/rip.mcollective.key")
        expect(security.sign("too many secrets")).to eq(signed)
      end
    end

    describe "#verify_signature" do
      let(:signed) { File.read("spec/fixtures/too_many_secrets.sig") }
      it "should correctly verify a signature" do
        security.stubs(:public_certfile).with("choria=rip.mcollective").returns("spec/fixtures/rip.mcollective.pem")
        expect(security.verify_signature("too many secrets", signed, "choria=rip.mcollective")).to be_truthy
      end

      it "should allow a privileged user cert to sign for a different callerid" do
        security.stubs(:public_certfile).with("choria=rspec.mcollective").returns("/nonexisting")
        security.stubs(:public_certfile).with("choria=nonexisting").returns("/nonexisting")
        security.stubs(:public_certfile).with("choria=rip.mcollective").returns("spec/fixtures/rip.mcollective.pem")
        security.stubs(:privilegeduser_certs).returns(["/nonexisting", "spec/fixtures/rip.mcollective.pem"])
        expect(security.verify_signature("too many secrets", signed, "choria=rspec.mcollective", true)).to be_truthy
      end
    end

    describe "#hash" do
      it "should produce a valid SHA256 hash" do
        expect(security.hash("too many secrets")).to eq("Yk+jdKdZ3v8E2p6dmbfn+ZN9lBBAHEIcOMp4lzuYKTo=")
      end
    end

    describe "#to_legacy_request" do
      it "should produce a valid request" do
        body = security.empty_request
        body["message"] = "r_message"

        %w[senderid requestid filter collective agent callerid ttl time].each do |k|
          body["envelope"][k] = "r_%s" % k
        end

        expected = Hash[%w[senderid requestid filter collective agent callerid ttl].map do |k|
          [k.intern, "r_%s" % k]
        end]

        expected[:body] = "r_message"
        expected[:msgtime] = "r_time"

        expect(security.to_legacy_request(body)).to eq(expected)
      end
    end

    describe "#to_legacy_reply" do
      it "should produce a valid reply" do
        body = security.empty_reply
        body["envelope"]["senderid"] = "r_senderid"
        body["envelope"]["requestid"] = "r_requestid"
        body["envelope"]["agent"] = "r_agent"
        body["envelope"]["time"] = "r_time"
        body["message"] = "r_message"

        expect(security.to_legacy_reply(body)).to eq(
          :senderid => "r_senderid",
          :requestid => "r_requestid",
          :senderagent => "r_agent",
          :msgtime => "r_time",
          :body => "r_message"
        )
      end
    end
  end
end

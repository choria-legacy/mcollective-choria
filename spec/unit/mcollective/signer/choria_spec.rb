require "spec_helper"

require "mcollective/security/choria"
require "mcollective/signer/choria"

module MCollective
  describe Signer::Choria do
    let(:signer) { Signer::Choria.new }
    let(:security) { Security::Choria.new }

    before(:each) do
      Config.instance.pluginconf.clear
      MCollective::PluginManager.stubs(:[]).with("security_plugin").returns(security)
      security.stubs(:current_timestamp).returns(1464002319)
    end

    describe "#remote_sign" do
      before(:each) do
        Config.instance.pluginconf["choria.security.request_signer.url"] = "http://localhost:8080/choria/v1/sign"
        ENV["choria_token"] = "test_env_token"
        Config.instance.pluginconf["choria.security.request_signer.token_environment"] = "choria_token"
      end

      it "should handle succesful signs" do
        signed = {
          "message" => "too many secrets",
          "signature" => File.read("spec/fixtures/too_many_secrets.sig"),
          "pubcert" => File.read("spec/fixtures/rip.mcollective.pem").chomp
        }.to_json

        response = {"secure_request" => Base64.encode64(signed)}.to_json

        stub_request(:post, "http://localhost:8080/choria/v1/sign").to_return(:status => 200, :body => response)

        sr = {"message" => "too many secrets"}
        signer.remote_sign!(sr)

        expect(sr["signature"]).to eq(File.read("spec/fixtures/too_many_secrets.sig"))
        expect(sr["pubcert"]).to eq(File.read("spec/fixtures/rip.mcollective.pem").chomp)
      end

      it "should handle signs with a error" do
        response = {"secure_request" => "", "error" => "simulated failure"}.to_json
        stub_request(:post, "http://localhost:8080/choria/v1/sign").to_return(:status => 200, :body => response)

        sr = {"message" => "too many secrets"}

        expect { signer.remote_sign!(sr) }.to raise_error("Could not get remote signature: simulated failure")
      end

      it "should handle request failures" do
        stub_request(:post, "http://localhost:8080/choria/v1/sign").to_return(:status => 500, :body => "not available")

        sr = {"message" => "too many secrets"}

        expect { signer.remote_sign!(sr) }.to raise_error("Could not get remote signature: 500: not available")
      end
    end

    describe "#local_sign" do
      it "should correctly sign the request" do
        security.initiated_by = :client
        security.choria.expects(:client_private_key).returns("spec/fixtures/rip.mcollective.key").twice
        security.choria.expects(:client_public_cert).returns("spec/fixtures/rip.mcollective.pem")

        sr = {"message" => "too many secrets"}
        signer.local_sign!(sr)
        expect(sr["signature"]).to eq(File.read("spec/fixtures/too_many_secrets.sig"))
        expect(sr["pubcert"]).to eq(File.read("spec/fixtures/rip.mcollective.pem").chomp)
      end
    end

    describe "#remote_signer_url" do
      it "should support unset" do
        expect(signer.remote_signer_url).to be_nil
      end

      it "should support empty" do
        Config.instance.pluginconf["choria.security.request_signer.url"] = ""
        expect(signer.remote_signer_url).to be_nil
      end

      it "should parse the url" do
        Config.instance.pluginconf["choria.security.request_signer.url"] = "https://localhost:8080"
        uri = signer.remote_signer_url
        expect(uri.host).to eq("localhost")
        expect(uri.port).to eq(8080)
      end
    end

    describe "#remote_signer?" do
      it "should support unset urls" do
        expect(signer.remote_signer?).to be(false)
      end

      it "should support '' urls" do
        Config.instance.pluginconf["choria.security.request_signer.url"] = ""
        expect(signer.remote_signer?).to be(false)
      end

      it "should support set urls" do
        Config.instance.pluginconf["choria.security.request_signer.url"] = "http://localhost:8080"
        expect(signer.remote_signer?).to be(true)
      end
    end

    describe "#token" do
      it "should support file tokens" do
        file = Tempfile.new("token")
        file.write("test_token")
        file.close

        Config.instance.pluginconf["choria.security.request_signer.token_file"] = file.path

        begin
          expect(signer.token).to eq("test_token")
        ensure
          file.unlink
        end
      end

      it "should support environment tokens" do
        ENV["choria_token"] = "test_env_token"
        Config.instance.pluginconf["choria.security.request_signer.token_environment"] = "choria_token"
        expect(signer.token).to eq("test_env_token")
      end
    end

    describe "sign_secure_request!" do
      it "should support disabling protocol security" do
        $choria_unsafe_disable_protocol_security = true # rubocop:disable Style/GlobalVars
        signer.expects(:remote_signer?).never

        begin
          signer.sign_secure_request!({})
        ensure
          $choria_unsafe_disable_protocol_security = false # rubocop:disable Style/GlobalVars
        end
      end

      it "should support remote signing" do
        Config.instance.pluginconf["choria.security.request_signer.url"] = "http://localhost:8080"
        signer.expects(:remote_sign!).once
        signer.sign_secure_request!({})
      end

      it "should support local signing" do
        Config.instance.pluginconf.delete("choria.security.request_signer.url")
        signer.expects(:local_sign!).once
        signer.sign_secure_request!({})
      end
    end

    describe "#sign_request_body" do
      it "should create the correct body" do
        ENV["CHORIA_TOKEN"] = "test_env_token"
        Config.instance.pluginconf["choria.security.request_signer.token_environment"] = "CHORIA_TOKEN"

        result = signer.sign_request_body("message" => "hello world")
        expect(result["token"]).to eq("test_env_token")
        expect(result["request"]).to eq(Base64.encode64("hello world"))
      end
    end
  end
end

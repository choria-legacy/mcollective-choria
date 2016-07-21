require "spec_helper"
require "mcollective/util/choria"

module MCollective
  module Util
    describe Choria do
      let(:choria) { Choria.new("production", false) }
      let(:parsed_app) { JSON.parse(File.read("spec/fixtures/sample_app.json")) }

      before(:each) do
        choria.stubs(:say)
      end

      describe "#ca_path" do
        it "should get the right path in ssl_dir" do
          choria.expects(:ssl_dir).returns("/ssl")
          expect(choria.ca_path).to eq("/ssl/certs/ca.pem")
        end
      end

      describe "#client_public_cert" do
        it "should get the right path in ssl_dir" do
          choria.expects(:ssl_dir).returns("/ssl")
          choria.expects(:certname).returns("rspec")
          expect(choria.client_public_cert).to eq("/ssl/certs/rspec.pem")
        end
      end

      describe "#client_private_key" do
        it "should get the right path in ssl_dir" do
          choria.expects(:ssl_dir).returns("/ssl")
          choria.expects(:certname).returns("rspec")
          expect(choria.client_private_key).to eq("/ssl/private_keys/rspec.pem")
        end
      end

      describe "#certname" do
        it "should take identity for root" do
          Process.expects(:uid).returns(0)
          expect(choria.certname).to eq("rspec_identity")
        end

        it "should support USER environment" do
          choria.expects(:env_fetch).with("USER", "rspec_identity").returns("rip")
          choria.expects(:env_fetch).with("MCOLLECTIVE_CERTNAME", "rip.mcollective").returns("rip.mcollective")
          expect(choria.certname).to eq("rip.mcollective")
        end

        it "should be overridable by MCOLLECTIVE_CERTNAME" do
          choria.expects(:env_fetch).with("USER", "rspec_identity").returns("rspec_identity")
          choria.expects(:env_fetch).with("MCOLLECTIVE_CERTNAME", "rspec_identity.mcollective").returns("rip.mcollective")
          expect(choria.certname).to eq("rip.mcollective")
        end
      end

      describe "#ssl_dir" do
        it "should support windows" do
          Util.expects(:windows?).returns(true)
          expect(choria.ssl_dir).to eq('C:\ProgramData\PuppetLabs\puppet\etc\ssl')
        end

        it "should support root on unix" do
          Util.expects(:windows?).returns(false)
          Process.expects(:uid).returns(0)
          expect(choria.ssl_dir).to eq("/etc/puppetlabs/puppet/ssl")
        end

        it "should support users" do
          Util.expects(:windows?).returns(false)
          Process.expects(:uid).returns(500)
          File.expects(:expand_path).with("~/.puppetlabs/etc/puppet/ssl").returns("/rspec/.puppetlabs/etc/puppet/ssl")
          expect(choria.ssl_dir).to eq("/rspec/.puppetlabs/etc/puppet/ssl")
        end
      end

      describe "#puppet_port" do
        it "should get the option from config, default to 8140" do
          Config.instance.stubs(:pluginconf).returns("puppet.port" => "8141")
          expect(choria.puppet_port).to eq("8141")

          Config.instance.stubs(:pluginconf).returns({})
          expect(choria.puppet_port).to eq("8140")
        end
      end

      describe "#puppet_server" do
        it "should ge the option from config, defualting to puppet" do
          Config.instance.stubs(:pluginconf).returns("puppet.host" => "rspec.puppet")
          expect(choria.puppet_server).to eq("rspec.puppet")

          Config.instance.stubs(:pluginconf).returns({})
          expect(choria.puppet_server).to eq("puppet")
        end
      end

      describe "check_ssl_setup" do
        before(:each) do
          choria.stubs(:client_public_cert).returns(File.expand_path("spec/fixtures/rip.mcollective.pem"))
          choria.stubs(:client_private_key).returns(File.expand_path("spec/fixtures/rip.mcollective.key"))
          choria.stubs(:ca_path).returns(File.expand_path("spec/fixtures/ca_crt.pem"))
        end

        it "should by default find all files" do
          expect(choria.check_ssl_setup).to be_truthy
        end

        it "fail if any files are missing" do
          choria.expects(:client_public_cert).returns("/nonexisting")

          expect {
            choria.check_ssl_setup
          }.to raise_error("Client SSL is not correctly setup, please use 'mco request_cert'")
        end
      end

      describe "#fetch_environment" do
        it "should fetch the right environment over https expecting JSON" do
          stub_request(:get, "https://puppet:8140/puppet/v3/environment/production")
            .with(:headers => {"Accept" => "application/json"})
            .to_return(:status => [500, "Internal Server Error"], :body => "failed")

          expect {
            choria.fetch_environment
          }.to raise_error("Failed to make request to Puppet: 500: Internal Server Error: failed")
        end

        it "should report error for non 200 replies" do
          stub_request(:get, "https://puppet:8140/puppet/v3/environment/production")
            .to_return(:status => 200, :body => File.read("spec/fixtures/sample_app.json"))

          expect(choria.fetch_environment).to eq(parsed_app)
        end
      end

      describe "#https" do
        it "should create a valid http client" do
          h = choria.https

          expect(h.use_ssl?).to be_truthy
          expect(h.verify_mode).to be(OpenSSL::SSL::VERIFY_PEER)
          expect(h.cert.subject.to_s).to eq("/CN=rip.mcollective")
          expect(h.ca_file).to eq(choria.ca_path)
          expect(h.key.to_pem).to eq(File.read(choria.client_private_key))
        end
      end
    end
  end
end

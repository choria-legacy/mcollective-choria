require "spec_helper"

require "mcollective/connector/nats"

module MCollective
  describe Connector::Nats do
    let(:connector) { Connector::Nats.new }
    let(:choria) { connector.choria }
    let(:connection) { connector.connection }
    let(:msg) { Message.new(Base64.encode64("rspec"), mock, :base64 => true, :headers => {}) }

    before(:each) do
      connector.stubs(:current_time).returns(Time.at(1466589505))
      connector.stubs(:current_pid).returns(999999)

      choria.stubs(:ssl_dir).returns("/ssl")
      choria.stubs(:certname).returns("rspec_identity")
      choria.stubs(:check_ssl_setup)

      msg.agent = "rspec_agent"
      msg.collective = "mcollective"
    end

    describe "#stats" do
      it "should get the stats from the wrapper" do
        connection.expects(:stats).returns(:stats => 1)
        expect(connector.stats).to eq(:stats => 1)
      end
    end

    describe "#connected_server" do
      it "should get the server when connected" do
        connection.expects(:connected_server).returns("nats.example.net")
        expect(connector.connected_server).to eq("nats.example.net")
      end
    end

    describe "#connected?" do
      it "should proxy to the wrapper" do
        connection.expects(:connected?).returns(false)
        expect(connector.connected?).to be(false)
      end
    end

    describe "#ssl_context" do
      it "should create a valid ssl context" do
        choria.stubs(:ca_path).returns("spec/fixtures/ca_crt.pem")
        choria.stubs(:client_public_cert).returns("spec/fixtures/rip.mcollective.pem")
        choria.stubs(:client_private_key).returns("spec/fixtures/rip.mcollective.key")

        context = connector.ssl_context

        expect(context.verify_mode).to be(OpenSSL::SSL::VERIFY_PEER)
        expect(context.ca_file).to eq("spec/fixtures/ca_crt.pem")
        expect(context.cert.subject.to_s).to eq("/CN=rip.mcollective")
        expect(context.key.to_pem).to eq(File.read("spec/fixtures/rip.mcollective.key"))
      end
    end

    describe "#server_list" do
      it "should create uris and credentials servers" do
        Config.instance.stubs(:pluginconf).returns("nats.user" => "rspec_user", "nats.pass" => "rspec_pass")
        choria.stubs(:middleware_servers).returns([["config", "1"], ["config", "2"]])
        expect(connector.server_list).to eq(["nats://rspec_user:rspec_pass@config:1", "nats://rspec_user:rspec_pass@config:2"])
      end
    end

    describe "#connect" do
      before(:each) do
        Process.stubs(:uid).returns(0)
        File.stubs(:readable?).returns(true)
        connector.stubs(:connection).returns(stub(:started? => false))
        connector.stubs(:server_list).returns(["nats://puppet:4222"])
      end

      it "should be noop when already connected" do
        connector.connection.stubs(:started? => true)
        connector.connection.expects(:start).never
        connector.connect
      end

      it "should connect" do
        mock_context = OpenSSL::SSL::SSLContext.new
        connector.stubs(:ssl_context).returns(mock_context)
        choria.expects(:randomize_middleware_servers?).returns(true)

        connector.connection.expects(:start).with(
          :max_reconnect_attempts => -1,
          :reconnect_time_wait => 1,
          :dont_randomize_servers => false,
          :name => "rspec_identity",
          :tls => {
            :context => mock_context
          },
          :servers => ["nats://puppet:4222"]
        )

        choria.expects(:check_ssl_setup)

        connector.connect
      end
    end

    describe "#headers_for" do
      it "should support :reply" do
        msg.type = :reply
        expect(connector.headers_for(msg)).to eq("mc_sender" => "rspec_identity")
      end

      it "should support requests" do
        msg.type = :request
        connector.expects(:make_target).with("rspec_agent", :reply, "mcollective").returns("rspec.reply.dest")
        expect(connector.headers_for(msg)).to eq(
          "mc_sender" => "rspec_identity",
          "reply-to" => "rspec.reply.dest"
        )
      end
    end

    describe "#target_for" do
      let(:request) { Message.new(Base64.encode64("rspec"), mock, :base64 => true, :headers => {}) }

      before(:each) do
        msg.stubs(:request).returns(request)
      end

      it "should support :reply" do
        msg.type = :reply

        expect { connector.target_for(msg) }.to raise_error(/Do not know how to reply/)

        request.headers["reply-to"] = "rspec.reply-to"

        expect(connector.target_for(msg)).to eq(
          :name => "rspec.reply-to",
          :headers => {
            "mc_sender" => "rspec_identity"
          }
        )
      end

      it "should support :request, :direct_request" do
        msg.type = :request

        connector.expects(:make_target).with("rspec_agent", :request, "mcollective", nil).returns("rspec.dest.1")
        connector.expects(:make_target).with("rspec_agent", :reply, "mcollective").returns("rspec.dest.2")

        expect(connector.target_for(msg)).to eq(
          :name => "rspec.dest.1",
          :headers => {
            "mc_sender" => "rspec_identity",
            "reply-to" => "rspec.dest.2"
          }
        )
      end
    end

    describe "#make_target" do
      it "should do input validation" do
        expect {
          connector.make_target("rspec", :rspec, "rspec")
        }.to raise_error("Unknown target type rspec")

        expect {
          connector.make_target("rspec", :reply, "rspec")
        }.to raise_error("Unknown collective 'rspec' known collectives are 'mcollective'")
      end

      it "should support :reply" do
        expect(connector.make_target("rspec_agent", :reply, "mcollective")).to eq("mcollective.reply.rspec_identity.999999.0")
        expect(connector.make_target("rspec_agent", :reply, "mcollective", "rsi")).to eq("mcollective.reply.rsi.999999.0")
      end

      it "should support :broadcast and :request" do
        [:broadcast, :request].each do |type|
          expect(connector.make_target("rspec_agent", type, "mcollective")).to eq("mcollective.broadcast.agent.rspec_agent")
        end
      end

      it "should support :direct requests" do
        [:direct_request, :directed].each do |type|
          expect(connector.make_target("rspec_agent", type, "mcollective")).to eq("mcollective.node.rspec_identity")
        end
      end
    end

    describe "#publish" do
      before(:each) do
        msg.collective = "mcollective"
        msg.agent = "rspec_agent"
      end

      it "should support direct requests" do
        msg.discovered_hosts = ["rspec1", "rspec2"]
        msg.type = :direct_request

        connector.connection.expects(:publish).with("mcollective.node.rspec1", any_parameters)
        connector.connection.expects(:publish).with("mcollective.node.rspec2", any_parameters)

        connector.publish(msg)
      end

      it "should support broacasts" do
        msg.type = :request
        connector.connection.expects(:publish).with("mcollective.broadcast.agent.rspec_agent", any_parameters)

        connector.publish(msg)
      end
    end

    describe "#unsubscribe" do
      it "should calculate the target and unsubscribe" do
        connection = stub
        connector.stubs(:connection).returns(connection)
        connection.expects(:unsubscribe).with("mcollective.broadcast.agent.rspec")

        connector.unsubscribe("rspec", :broadcast, "mcollective")
      end
    end

    describe "#subscribe" do
      it "should calculate the target and subscribe" do
        connection = stub
        connector.stubs(:connection).returns(connection)
        connection.expects(:subscribe).with("mcollective.broadcast.agent.rspec")

        connector.subscribe("rspec", :broadcast, "mcollective")
      end
    end

    describe "#receive" do
      let(:rawmsg) { {"data" => "rspec"} }
      let(:connection) { stub }

      before(:each) do
        connector.stubs(:connection).returns(connection)
      end

      it "should receive until a valid message is found" do
        connection.expects(:receive).returns(nil, rawmsg.to_json).twice
        expect(connector.receive.message).to eq(rawmsg)
      end

      it "should not die on invalid json" do
        connection.expects(:receive).returns("invalid", rawmsg.to_json).twice
        Log.expects(:warn).with(regexp_matches(/Got non JSON data from the broker/))

        expect(connector.receive.message).to eq(rawmsg)
      end
    end

    describe "#decorate_servers_with_users" do
      it "should add user and pass properties from config" do
        Config.instance.stubs(:pluginconf).returns("nats.user" => "rspec_user", "nats.pass" => "rspec_pass")

        list = connector.decorate_servers_with_users([URI("nats://r:1"), URI("nats://r:2")])

        list.each do |uri|
          expect(uri.user).to eq("rspec_user")
          expect(uri.password).to eq("rspec_pass")
        end
      end

      it "should add user and pass properties from ENV" do
        connector.stubs(:environment).returns("MCOLLECTIVE_NATS_USERNAME" => "rspec_env_user", "MCOLLECTIVE_NATS_PASSWORD" => "rspec_env_pass")
        list = connector.decorate_servers_with_users([URI("nats://r:1"), URI("nats://r:2")])

        list.each do |uri|
          expect(uri.user).to eq("rspec_env_user")
          expect(uri.password).to eq("rspec_env_pass")
        end
      end

      it "should do nothing when not configured" do
        connector.stubs(:environment).returns({})
        Config.instance.stubs(:pluginconf).returns({})

        list = connector.decorate_servers_with_users([URI("nats://r:1"), URI("nats://r:2")])

        list.each do |uri|
          expect(uri.user).to be_nil
          expect(uri.password).to be_nil
        end
      end
    end

    describe "#get_option" do
      it "should find the configured option" do
        Config.instance.stubs(:pluginconf).returns("rspec" => "rspec_answer")
        expect(connector.get_option("rspec")).to eq("rspec_answer")
      end

      it "should fail when not found without a default" do
        expect {
          connector.get_option("rspec")
        }.to raise_error("No plugin.rspec configuration option given")
      end

      it "should support a default" do
        expect(connector.get_option("rspec", "default")).to eq("default")
      end
    end
  end
end

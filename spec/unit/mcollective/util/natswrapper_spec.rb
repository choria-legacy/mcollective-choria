require "spec_helper"
require "mcollective/util/natswrapper"

module MCollective
  describe Util::NatsWrapper do
    let(:wrapper) { Util::NatsWrapper.new }
    let(:client) do
      stub(
        :options => {:nats => "options"},
        :connected? => true,
        :connected_server => "rspec.example.net:1234"
      )
    end

    before(:each) do
      wrapper.stub_client(client)
    end

    describe "#active_options" do
      it "should get the options from the client" do
        expect(wrapper.active_options).to eq(:nats => "options")
      end
    end

    describe "#client_version" do
      it "should return the gem version" do
        expect(wrapper.client_version).to eq(NATS::IO::VERSION)
      end
    end

    describe "#client_flavour" do
      it "should return nats-pure" do
        expect(wrapper.client_flavour).to eq("nats-pure")
      end
    end

    describe "#connected_server" do
      it "should be nil when not connected" do
        client.expects(:connected?).returns(false)
        expect(wrapper.connected_server).to be_nil
      end

      it "should get the connected server" do
        expect(wrapper.connected_server).to eq("rspec.example.net:1234")
      end
    end

    describe "#stats" do
      it "should be empty when there is no client" do
        wrapper.expects(:has_client?).returns(false)
        expect(wrapper.stats).to eq({})
      end

      it "should ge the client stats" do
        client.expects(:stats).returns(:stats => 1)
        expect(wrapper.stats).to eq(:stats => 1)
      end
    end

    describe "#start" do
      it "should have tests"
    end

    describe "#stop" do
      it "should stop NATS" do
        client.expects(:close)
        wrapper.stop
      end
    end

    describe "#receive" do
      it "should receive from the queue" do
        wrapper.received_queue << "msg"
        expect(wrapper.received_queue.size).to be(1)
        expect(wrapper.receive).to eq("msg")
        expect(wrapper.received_queue.size).to be(0)
      end
    end

    describe "#publish" do
      it "should publish to NATS" do
        client.expects(:publish).with("rspec.dest", "msg", "rspec.reply")
        wrapper.publish("rspec.dest", "msg", "rspec.reply")
      end
    end

    describe "#subscribe" do
      it "should subscribe only once" do
        client.stubs(:subscribe).with("rspec.dest", {}).yields("msg", "x", "sub").returns(1).once

        wrapper.subscribe("rspec.dest")
        expect(wrapper.subscriptions).to have_key("rspec.dest")
        wrapper.subscribe("rspec.dest")
        expect(wrapper.receive).to eq("msg")
      end

      it "should support options" do
        client.expects(:subscribe).with("x", :queue => "y").returns(1)
        wrapper.subscribe("x", :queue => "y")
      end
    end

    describe "#unsubscribe" do
      it "should unsubscribe only once" do
        client.stubs(:subscribe).yields("msg", "x", "sub").returns(1)

        wrapper.subscribe("rspec.dest")

        client.expects(:unsubscribe).with(1).once

        wrapper.unsubscribe("rspec.dest")
        wrapper.unsubscribe("rspec.dest")
      end
    end
  end
end

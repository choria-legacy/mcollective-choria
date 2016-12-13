require "spec_helper"

require "mcollective/util/natswrapper"

module MCollective
  describe Util::NatsWrapper do
    let(:wrapper) { Util::NatsWrapper.new }
    let(:client) { stub(:connected? => true, :connected_server => "rspec.example.net:1234") }

    before(:each) do
      wrapper.stub_client(client)
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
        client.stubs(:subscribe).yields("msg", "x", "sub").returns(1).once

        wrapper.subscribe("rspec.dest")
        expect(wrapper.subscriptions).to have_key("rspec.dest")
        wrapper.subscribe("rspec.dest")
        expect(wrapper.receive).to eq("msg")
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

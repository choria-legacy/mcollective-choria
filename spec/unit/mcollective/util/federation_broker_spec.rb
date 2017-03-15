require "spec_helper"
require "mcollective/util/federation_broker"

module MCollective
  module Util
    describe FederationBroker do
      let(:fb) { FederationBroker.new("rspec", "test") }

      describe "#stats_port" do
        it "should accept a given port" do
          fb.choria.expects(:stats_port).never
          expect(FederationBroker.new("rspec", "test", 1235).stats_port).to eq(1235)
        end

        it "should consult choria" do
          fb.choria.expects(:stats_port).returns(1234)
          expect(fb.stats_port).to be(1234)
        end
      end

      describe "#record_thread" do
        it "should record the thread by name" do
          expect(fb.threads).to_not include("rspec")
          fb.record_thread("rspec", t = Thread.new {})
          expect(fb.threads["rspec"]).to be(t)
          expect(fb.threads["rspec"]["_name"]).to eq("rspec")
        end

        it "should fail for dup thread names" do
          fb.record_thread("rspec", Thread.new {})
          expect { fb.record_thread("rspec", stub) }.to raise_error("Thread called 'rspec' already exist in the thread registry")
        end
      end

      describe "#ok?" do
        it "should be success if all alive" do
          t = Thread.new { sleep 10 }
          fb.record_thread("rspec", t)
          expect(fb.ok?).to be(true)
        end

        it "should not be ok when not all are alive" do
          t = Thread.new { raise }
          Thread.kill(t)

          10.times { Thread.pass }

          fb.record_thread("rspec", t)
          expect(fb.ok?).to be(false)
        end
      end

      describe "#thread_status" do
        it "should include all recorded threads" do
          fb.record_thread("rspec", Thread.new { sleep 1})
          expect(fb.thread_status).to include(
            "rspec" => {"alive" => true, "status" => "run"}
          )
        end
      end

      describe "#start" do
        it "should start and store all threads and set it started" do
          FederationBroker::CollectiveProcessor.expects(:new).with(fb, instance_of(Queue), instance_of(Queue)).returns(cp = stub)
          FederationBroker::FederationProcessor.expects(:new).with(fb, instance_of(Queue), instance_of(Queue)).returns(fp = stub)

          cp.expects(:start).returns(cc = stub)
          fp.expects(:start).returns(fc = stub)

          expect(fb.started?).to be(false)
          fb.start
          expect(fb.started?).to be(true)

          expect(fb.connections["collective"]).to be(cc)
          expect(fb.connections["federation"]).to be(fc)
        end
      end
    end
  end
end

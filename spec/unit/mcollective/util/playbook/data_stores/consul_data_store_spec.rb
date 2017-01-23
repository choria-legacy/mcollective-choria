require "spec_helper"
require "mcollective/util/playbook"
require "diplomat"

module MCollective
  module Util
    class Playbook
      class DataStores
        describe ConsulDataStore do
          let(:ds) { ConsulDataStore.new("rspec", stub) }

          before(:each) do
            ds.from_hash(
              "timeout" => 1,
              "ttl" => 2
            )
          end

          describe "#session" do
            it "should make a new session and start the manager" do
              Diplomat::Session.expects(:create).with("TTL" => "10s", "Behavior" => "delete").returns("rspec-session")
              ds.expects(:start_session_manager)

              expect(session = ds.session).to eq("rspec-session")
              expect(ds.session).to be(session)
            end
          end

          describe "#renew_session" do
            it "should renew the session and handle failures" do
              ds.instance_variable_set("@session_id", "rspec-session")
              Diplomat::Session.expects(:renew).with("rspec-session")

              ds.renew_session
            end
          end

          describe "#ttl" do
            it "should handle negative numbers" do
              ds.from_hash("ttl" => -1)
              expect(ds.ttl).to be(10)
            end

            it "should force to at least 10" do
              ds.from_hash("ttl" => 5)
              expect(ds.ttl).to be(10)

              ds.from_hash("ttl" => 11)
              expect(ds.ttl).to be(11)
            end
          end

          describe "#lock" do
            it "should create the right lock" do
              ds.stubs(:session).returns("rspec-session")
              Diplomat::Lock.expects(:wait_to_acquire).with("x", "rspec-session", nil, 2)
              ds.lock("x", 10)
            end

            it "should handle timeouts" do
              ds.stubs(:session).returns("rspec-session")
              Diplomat::Lock.expects(:wait_to_acquire).with("x", "rspec-session", nil, 2).raises(Timeout::Error, "rspec timeout")

              expect { ds.lock("x", 10) }.to raise_error("Failed to obtain lock x after 10 seconds")
            end
          end

          describe "#release" do
            it "should release the right lock" do
              ds.stubs(:session).returns("rspec-session")
              Diplomat::Lock.expects(:release).with("x", "rspec-session")
              ds.release("x")
            end
          end

          describe "#delete" do
            it "should delete the data" do
              Diplomat::Kv.expects(:delete).with("x")
              ds.delete("x")
            end
          end

          describe "#write" do
            it "should store the data" do
              Diplomat::Kv.expects(:put).with("x", "value")
              ds.write("x", "value")
            end
          end

          describe "#read" do
            it "should read the data" do
              Diplomat::Kv.expects(:get).with("x").returns("value")
              expect(ds.read("x")).to eq("value")
            end
          end
        end
      end
    end
  end
end

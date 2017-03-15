require "spec_helper"
require "mcollective/util/federation_broker"

module MCollective
  module Util
    class FederationBroker
      describe CollectiveProcessor do
        let(:fb) { stub(:cluster_name => "rspec", :instance_name => "a") }
        let(:inbox) { stub }
        let(:outbox) { stub }
        let(:nats) { stub(:connected_server => "rspec.local") }
        let(:cp) { CollectiveProcessor.new(fb, inbox, outbox) }

        describe "#process" do
          it "should add the correct message to the outbox" do
            msg = {
              "body" => "body",
              "headers" => {
                "federation" => {
                  "req" => "rspecreq",
                  "reply-to" => "x.y.z"
                }
              }
            }

            JSON.expects(:dump).with(
              "body" => "body",
              "headers" => {
                "seen-by" => ["fedbroker_rspec_a"],
                "federation" => {
                  "req" => "rspecreq"
                }
              }
            ).returns("dumped_json")

            outbox.expects(:<<).with(
              :targets => ["x.y.z"],
              :req => "rspecreq",
              :data => "dumped_json"
            )

            cp.process(msg)
          end
        end

        describe "#queue" do
          it "should be correct" do
            expect(cp.queue).to eq(
              :name => "choria.federation.rspec.collective",
              :queue => "rspec_collective"
            )
          end
        end

        describe "#processor_type" do
          it "should be collective" do
            expect(cp.processor_type).to eq("collective")
          end
        end

        describe "#servers" do
          it "should get choria middleware servers" do
            cp.choria.stubs(:middleware_servers).with("puppet", "4222").returns([["rspec1", "4222"], ["rspec2", "4223"]])
            expect(cp.servers).to eq(["nats://rspec1:4222", "nats://rspec2:4223"])
          end
        end
      end
    end
  end
end

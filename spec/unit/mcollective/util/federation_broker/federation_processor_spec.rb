require "spec_helper"
require "mcollective/util/federation_broker"

module MCollective
  module Util
    class FederationBroker
      describe FederationProcessor do
        let(:fb) { stub(:cluster_name => "rspec", :instance_name => "a") }
        let(:inbox) { stub }
        let(:outbox) { stub }
        let(:nats) { stub(:connected_server => "rspec.local") }
        let(:fp) { FederationProcessor.new(fb, inbox, outbox) }

        describe "#process" do
          it "should add the correct message to the outbox" do
            msg = {
              "body" => "body",
              "headers" => {
                "reply-to" => "x.y.z",
                "federation" => {
                  "target" => ["broadcast.discovery.agent"],
                  "req" => "rspecreq"
                }
              }
            }

            JSON.expects(:dump).with(
              "body" => "body",
              "headers" => {
                "federation" => {
                  "req" => "rspecreq",
                  "reply-to" => "x.y.z"
                },
                "reply-to" => "choria.federation.rspec.collective",
                "seen-by" => ["fedbroker_rspec_a"]
              }
            ).returns("dumped_json")

            outbox.expects(:<<).with(
              :targets => ["broadcast.discovery.agent"],
              :req => "rspecreq",
              :data => "dumped_json"
            )

            fp.process(msg)
          end
        end

        describe "#queue" do
          it "should be correct" do
            expect(fp.queue).to eq(
              :name => "choria.federation.rspec.federation",
              :queue => "rspec_federation"
            )
          end
        end

        describe "#processor_type" do
          it "should be collective" do
            expect(fp.processor_type).to eq("federation")
          end
        end

        describe "#servers" do
          it "should get choria middleware servers" do
            fp.choria.stubs(:federation_middleware_servers).returns([["rspec1", "4222"], ["rspec2", "4223"]])
            expect(fp.servers).to eq(["nats://rspec1:4222", "nats://rspec2:4223"])
          end
        end
      end
    end
  end
end

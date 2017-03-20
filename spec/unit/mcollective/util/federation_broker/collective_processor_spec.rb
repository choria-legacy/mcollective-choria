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

        describe "#should_process?" do
          it "should not accept !hashes" do
            Log.expects(:warn).with(regexp_matches(/Received a non hash message/))
            expect(cp.should_process?("X")).to be(false)
          end

          it "should only accept messages with headers" do
            Log.expects(:warn).with(regexp_matches(/Received a message without headers/))
            expect(cp.should_process?({})).to be(false)
          end

          it "should only accept messages with federation markup" do
            Log.expects(:warn).with(regexp_matches(/Received an unfederated message/))
            expect(cp.should_process?("headers" => {})).to be(false)
          end

          it "should only accept messages with a reply-to federation header" do
            Log.expects(:warn).with(regexp_matches(/Received an invalid reply to header in the federation structure/))
            expect(cp.should_process?("headers" => {"federation" => {}})).to be(false)
          end

          it "should only accept messages with valid reply headers" do
            msg = {
              "headers" => {
                "federation" => {
                  "reply-to" => "choria.federation.production.federation"
                }
              }
            }

            Log.expects(:warn).with(regexp_matches(/Received a collective message with an unexpected reply to target 'choria.federation.production.federation'/))
            expect(cp.should_process?(msg)).to be(false)
          end

          it "should accept valid messages" do
            msg = {
              "headers" => {
                "federation" => {
                  "reply-to" => "rspec.reply.x.y.z"
                }
              }
            }

            expect(cp.should_process?(msg)).to be(true)
          end
        end

        describe "#process" do
          it "should add the correct message to the outbox" do
            msg = {
              "body" => "body",
              "headers" => {
                "federation" => {
                  "req" => "rspecreq",
                  "reply-to" => "rspec.reply.foo.1.1"
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
              :targets => ["rspec.reply.foo.1.1"],
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

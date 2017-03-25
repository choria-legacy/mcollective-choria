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

        describe "#should_process?" do
          it "should not accept !hashes" do
            Log.expects(:warn).with(regexp_matches(/Received a non hash message/))
            expect(fp.should_process?("X")).to be(false)
          end

          it "should only accept messages with headers" do
            Log.expects(:warn).with(regexp_matches(/Received a message without headers/))
            expect(fp.should_process?({})).to be(false)
          end

          it "should only accept messages with federation markup" do
            Log.expects(:warn).with(regexp_matches(/Received an unfederated message/))
            expect(fp.should_process?("headers" => {})).to be(false)
          end

          it "should only accept messages with a reply-to header" do
            Log.expects(:warn).with(regexp_matches(/Received an invalid reply to header/))
            expect(fp.should_process?("headers" => {"federation" => {}})).to be(false)
          end

          it "should only accept messages with a valid reply-to header" do
            msg = {
              "headers" => {
                "reply-to" => "rspec.x",
                "federation" => {}
              }
            }

            Log.expects(:warn).with(regexp_matches(/Received an invalid reply to target/))
            expect(fp.should_process?(msg)).to be(false)
          end

          it "should only accept valid targets" do
            msg = {
              "headers" => {
                "reply-to" => "rspec.reply.x.y.z",
                "federation" => {
                  "target" => [
                    "rspec.node.x.y",
                    "choria.federation.foo"
                  ]
                }
              }
            }

            Log.expects(:warn).with(regexp_matches(/Received an unexpected remote target 'choria.federation.foo/))
            expect(fp.should_process?(msg)).to be(false)
          end

          it "should accept valid messages" do
            msg = {
              "headers" => {
                "reply-to" => "rspec.reply.x.y.z",
                "federation" => {
                  "target" => [
                    "rspec.node.x.y",
                    "rspec.node.x.z",
                    "rspec.broadcast.agent.discovery"
                  ]
                }
              }
            }

            expect(fp.should_process?(msg)).to be(true)
          end
        end

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
                "reply-to" => "choria.federation.rspec.collective"
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

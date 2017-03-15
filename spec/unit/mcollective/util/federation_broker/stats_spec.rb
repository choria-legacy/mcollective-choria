require "spec_helper"
require "mcollective/util/federation_broker"

module MCollective
  module Util
    class FederationBroker
      describe Stats do
        let(:fb) { FederationBroker.new("rspec", "test") }
        let(:stats) { fb.stats }

        describe "#serve_stats" do
          it "should serve the right stats" do
            res = stub
            req = stub(:peeraddr => ["AF_INET", 80, "localhost", "127.0.0.1"])

            res.expects(:[]=).with("Content-Type", "application/json")
            stats.expects(:update_broker_stats).returns("rspec" => "stub")
            res.expects(:body=).with(JSON.pretty_generate("rspec" => "stub"))

            stats.serve_stats(req, res)
          end
        end

        describe "#update_broker_stats" do
          it "should fetch the right data" do
            fb.expects(:thread_status).returns("rspec" => {"alive" => true})
            fb.expects(:ok?).returns(true)
            fb.expects(:processors).returns(
              "collective" => stub(:stats => cs = stub),
              "federation" => stub(:stats => fs = stub)
            ).twice

            expect(stats.update_broker_stats).to include(
              "status" => "OK",
              "collective" => cs,
              "federation" => fs,
              "threads" => {
                "rspec" => {
                  "alive" => true
                }
              }
            )
          end
        end

        describe "#initial_stats" do
          it "should create the correct structure" do
            t = Time.now
            Time.stubs(:now).returns(t)
            Config.instance.stubs(:configfile).returns("/nonexisting")

            expect(stats.initial_stats).to eq(
              "version" => Choria::VERSION,
              "start_time" => t.to_i,
              "cluster" => "rspec",
              "instance" => "test",
              "config_file" => "/nonexisting",
              "status" => "unknown",
              "collective" => {},
              "federation" => {},
              "threads" => {},
              "/stats" => {
                "requests" => 0
              }
            )
          end
        end
      end
    end
  end
end

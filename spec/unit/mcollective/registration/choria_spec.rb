require "spec_helper"
require "mcollective/registration/choria"

module MCollective
  module Registration
    describe Choria do
      let(:choria) { Choria.new }
      let(:connection) { stub }

      before(:each) do
        choria.connection = connection
      end

      describe "#config" do
        it "should get the config instance" do
          expect(choria.config).to be(Config.instance)
        end
      end

      describe "#registration_data" do
        it "should return the right data" do
          t = Time.now
          Time.stubs(:now).returns(t)
          PluginManager.expects(:[]).with("global_stats").returns("g_stats" => 1)
          choria.expects(:connected_server).returns("nats.example.net")
          choria.expects(:connector_stats).returns("c_stats" => 1)
          expect(choria.registration_data).to eq(
            "timestamp" => t.to_i,
            "identity" => "rspec_identity",
            "version" => MCollective::VERSION,
            "stats" => {"g_stats" => 1},
            "nats" => {
              "connected_server" => "nats.example.net",
              "stats" => {"c_stats" => 1}
            }
          )
        end
      end

      describe "#registration_file" do
        it "should be configurable" do
          Config.instance.stubs(:pluginconf).returns("choria.registration.file" => "/nonexisting/stats")
          expect(choria.registration_file).to eq("/nonexisting/stats")
        end

        it "should default" do
          Config.instance.stubs(:logfile).returns("/nonexisting/mcollective.log")
          expect(choria.registration_file).to eq("/nonexisting/choria-stats.json")
        end
      end

      describe "#interval" do
        it "should get the right interval" do
          Config.instance.expects(:registerinterval).returns(10)
          expect(choria.interval).to be(10)
        end
      end

      describe "#connector_stats" do
        it "should fetch the connection stats" do
          connection.expects(:stats).returns(:stats => 1)
          expect(choria.connector_stats).to eq(:stats => 1)
        end
      end

      describe "#connected_server" do
        it "should return the server if connected" do
          connection.expects(:connected?).returns(true)
          connection.expects(:connected_server).returns("rspec.example.net")
          expect(choria.connected_server).to eq("rspec.example.net")
        end

        it "should handle disconnections" do
          connection.expects(:connected?).returns(false)
          expect(choria.connected_server).to eq("disconnected")
        end
      end

      describe "#publish" do
        it "should write the right file" do
          temp = stub(:path => "/nonexisting/xxxx", :close => nil)
          Config.instance.stubs(:logfile).returns("/nonexisting/mcollective.log")
          Tempfile.expects(:new).with("choria-stats.json", "/nonexisting").returns(temp)
          choria.expects(:registration_data).returns("rspec" => 1)
          temp.expects(:write).with({"rspec" => 1}.to_json)
          File.expects(:chmod).with(0o0644, "/nonexisting/xxxx")
          File.expects(:rename).with("/nonexisting/xxxx", "/nonexisting/choria-stats.json")

          choria.publish
        end
      end

      describe "#run" do
        it "should not run when interval is 0" do
          choria.stubs(:interval).returns(0)
          Thread.expects(:new).never
          expect(choria.run(stub)).to be(false)
        end

        it "should start the publisher" do
          choria.stubs(:interval).returns(5)
          choria.stubs(:registration_file).returns("/nonexisting/choria-stats.json")

          # this is pointless but mocha doesnt work with threads
          Thread.expects(:new).once
          choria.run(stub)
        end
      end
    end
  end
end

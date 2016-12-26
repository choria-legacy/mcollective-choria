require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      class Tasks
        describe SlackTask do
          let(:task) { SlackTask.new }

          describe "#run" do
            before(:each) do
              task.from_hash(
                "channel" => "#general",
                "text" => "hello rspec",
                "token" => "RSPEC_TOKEN",
                "username" => "Rspec Bot"
              )
            end

            it "should submit the right request to slack and handle success" do
              task.stubs(:choria).returns(choria = stub)
              choria.expects(:https).with(:target => "slack.com", :port => 443).returns(https = stub)
              choria.expects(:http_get).with("/api/chat.postMessage?token=RSPEC_TOKEN&username=Rspec%20Bot&channel=%23general&text=hello%20rspec").returns(get = stub)
              https.expects(:request).with(get).returns([stub(:code => "200", :body => JSON.dump("ok" => true))])

              expect(task.run).to eq(
                [
                  true,
                  "Message submitted to slack channel #general",
                  ["ok" => true]
                ]
              )
            end

            it "should handle failures" do
              task.stubs(:choria).returns(choria = stub)
              choria.expects(:https).with(:target => "slack.com", :port => 443).returns(https = stub)
              choria.expects(:http_get).with("/api/chat.postMessage?token=RSPEC_TOKEN&username=Rspec%20Bot&channel=%23general&text=hello%20rspec").returns(get = stub)
              https.expects(:request).with(get).returns([stub(:code => "500", :body => JSON.dump("ok" => false, "error" => "rspec error"))])

              expect(task.run).to eq(
                [
                  false,
                  "Failed to send message to slack channel #general: rspec error",
                  ["ok" => false, "error" => "rspec error"]
                ]
              )
            end
          end

          describe "#validate_configuration!" do
            it "should detect missing channels" do
              expect { task.validate_configuration! }.to raise_error("A channel is required")
            end

            it "should detect missing text" do
              task.from_hash(
                "channel" => "#general"
              )

              expect { task.validate_configuration! }.to raise_error("Message text is required")
            end

            it "should detect missing tokens" do
              task.from_hash(
                "channel" => "#general",
                "text" => "hello rspec"
              )

              expect { task.validate_configuration! }.to raise_error("A bot token is required")
            end

            it "should accept good configs" do
              task.from_hash(
                "channel" => "#general",
                "text" => "hello rspec",
                "token" => "RSPEC_TOKEN",
                "username" => "Rspec Bot"
              )

              task.validate_configuration!
            end
          end

          describe "#from_hash" do
            it "should parse correctly" do
              task.from_hash(
                "channel" => "#general",
                "text" => "hello rspec",
                "token" => "RSPEC_TOKEN",
                "username" => "Rspec Bot"
              )

              expect(task.instance_variable_get("@channel")).to eq("#general")
              expect(task.instance_variable_get("@text")).to eq("hello rspec")
              expect(task.instance_variable_get("@token")).to eq("RSPEC_TOKEN")
              expect(task.instance_variable_get("@username")).to eq("Rspec Bot")

              task.from_hash({})
              expect(task.instance_variable_get("@username")).to eq("Choria")
            end
          end
        end
      end
    end
  end
end

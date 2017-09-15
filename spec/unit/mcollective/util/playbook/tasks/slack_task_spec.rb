require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      class Tasks
        describe SlackTask do
          let(:playbook) { stub(:name => "rspec_playbook") }
          let(:task) { SlackTask.new(playbook) }

          before(:each) do
            PluginManager.stubs(:[]).with("security_plugin").returns(stub(:callerid => "choria=rspec"))
          end

          describe "#attachments" do
            before(:each) do
              task.from_hash(
                "channel" => "#general",
                "text" => "hello rspec",
                "token" => "RSPEC_TOKEN",
                "username" => "Rspec Bot"
              )

              task.description = "rspec task description"
            end

            it "should produce the right attachments" do
              expect(task.attachments).to eq(
                [
                  "fallback" => "hello rspec",
                  "color" => "#ffa449",
                  "text" => "hello rspec",
                  "pretext" => "Task: rspec task description",
                  "mrkdwn_in" => ["text"],
                  "footer" => "Choria Playbooks",
                  "fields" => [
                    {"title" => "user", "value" => "choria=rspec", "short" => true},
                    {"title" => "playbook", "value" => "rspec_playbook", "short" => true}
                  ]
                ]
              )
            end
          end

          describe "#run" do
            before(:each) do
              task.from_hash(
                "channel" => "#general",
                "text" => "hello rspec",
                "token" => "RSPEC_TOKEN",
                "username" => "Rspec Bot"
              )

              task.stubs(:attachments).returns([])
            end

            it "should submit the right request to slack and handle success" do
              task.stubs(:choria).returns(choria = stub)
              choria.expects(:https).with(:target => "slack.com", :port => 443).returns(https = stub)
              task.expects(:attachments).returns([])
              choria.expects(:http_get).with(
                "/api/chat.postMessage?token=RSPEC_TOKEN&username=Rspec+Bot&channel=%23general&icon_url=http%3A%2F%2Fchoria.io%2Fimg%2Fslack-48x48.png&attachments=%5B%5D"
              ).returns(get = stub)
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
              choria.expects(:http_get).with(
                "/api/chat.postMessage?token=RSPEC_TOKEN&username=Rspec+Bot&channel=%23general&icon_url=http%3A%2F%2Fchoria.io%2Fimg%2Fslack-48x48.png&attachments=%5B%5D"
              ).returns(get = stub)
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
                "username" => "Rspec Bot",
                "color" => "#12345"
              )

              expect(task.instance_variable_get("@channel")).to eq("#general")
              expect(task.instance_variable_get("@text")).to eq("hello rspec")
              expect(task.instance_variable_get("@token")).to eq("RSPEC_TOKEN")
              expect(task.instance_variable_get("@username")).to eq("Rspec Bot")
              expect(task.instance_variable_get("@color")).to eq("#12345")

              task.from_hash({})
              expect(task.instance_variable_get("@username")).to eq("Choria")
              expect(task.instance_variable_get("@color")).to eq("#ffa449")
            end
          end
        end
      end
    end
  end
end

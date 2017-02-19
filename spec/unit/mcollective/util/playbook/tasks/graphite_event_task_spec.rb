require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      class Tasks
        describe Graphite_eventTask do
          let(:task) { Graphite_eventTask.new(stub) }

          describe "#run" do
            it "should run the webhook" do
              task.expects(:webhook_task).returns(wh = stub)
              wh.expects(:run).returns([true, "success", []])
              expect(task.run).to eq([true, "success", []])
            end
          end

          describe "#webhook_task" do
            it "should create the right webhook task" do
              task.description = "rspec task"
              task.from_hash(
                "what" => "rspec what",
                "tags" => ["rspec", "tags"],
                "data" => "rspec data",
                "graphite" => "http://localhost"
              )

              task.expects(:request).returns("rspec" => "request")

              Tasks::WebhookTask.expects(:new).returns(wh = stub)
              wh.expects(:from_hash).with(
                "description" => "rspec task",
                "headers" => {},
                "uri" => "http://localhost",
                "method" => "POST",
                "data" => {"rspec" => "request"}
              )

              task.webhook_task
            end
          end

          describe "#request" do
            it "should create the correct task" do
              task.from_hash(
                "what" => "rspec what",
                "tags" => ["rspec", "tags"],
                "data" => "rspec data"
              )

              now = Time.now
              Time.expects(:now).returns(now)

              expect(task.request).to eq(
                "what" => "rspec what",
                "tags" => "rspec,tags",
                "when" => now.to_i,
                "data" => "rspec data"
              )
            end
          end

          describe "#validate_configuration!" do
            it "should excect required data" do
              task.from_hash({})
              expect { task.validate_configuration! }.to raise_error("The 'what' property is required")

              task.from_hash("what" => "rspec")
              expect { task.validate_configuration! }.to raise_error("The 'data' property is required")

              task.from_hash("what" => "rspec", "data" => "rspec data")
              expect { task.validate_configuration! }.to raise_error("The 'graphite' property is required")

              task.from_hash("what" => "rspec", "data" => "rspec data", "graphite" => "http://localhost", "tags" => "")
              expect { task.validate_configuration! }.to raise_error("'tags' should be an array")

              task.from_hash("what" => "rspec", "data" => "rspec data", "graphite" => "http://localhost", "headers" => "")
              expect { task.validate_configuration! }.to raise_error("'headers' should be a hash")

              task.from_hash("what" => "rspec", "data" => "rspec data", "graphite" => "rspec://localhost")
              expect { task.validate_configuration! }.to raise_error("The graphite url should be either http or https")
            end
          end
        end
      end
    end
  end
end

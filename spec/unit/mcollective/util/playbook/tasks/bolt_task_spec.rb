require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      class Tasks
        describe BoltTask do
          let(:task) { BoltTask.new(stub(:loglevel => "error")).tap(&:require_bolt) }
          let(:executor) { stub }

          before(:each) do
            task.stubs(:bolt_executor).returns(executor)
          end

          describe "#to_execution_result" do
            it "should return the result unmodified" do
              expect(task.to_execution_result([true, "test", {"result" => "rspec"}])).to eq("result" => "rspec")
            end
          end

          describe "#run" do
            it "should run tasks" do
              task.stubs(:current_time).returns(Time.now - 1)
              task.expects(:run_task).returns({})
              task.expects(:log_results).with({}, 1).returns([true, "rspec success", {}])

              task.from_hash("task" => "mymod::sample")

              expect(task.run).to eq([true, "rspec success", {}])
            end

            it "should run commands" do
              task.stubs(:current_time).returns(Time.now - 1)
              task.expects(:run_command).returns({})
              task.expects(:log_results).with({}, 1).returns([true, "rspec success", {}])

              task.from_hash("command" => "sample")

              expect(task.run).to eq([true, "rspec success", {}])
            end

            it "should fail for plans" do
              task.from_hash("plan" => "sample")

              expect(task.run).to eq([false, "Could not create Bolt action: RuntimeError: Executing Bolt plans is not currently supported", {}])
            end
          end

          describe "#log_results" do
            it "should log results correctly" do
              task.from_hash("nodes" => ["node1", "node2"])

              results = {
                stub(:host => "node1") => stub(:success? => true, :message => "message 1"),
                stub(:host => "node2") => stub(:success? => false, :message => "message 2")
              }

              Log.expects(:info).with("Success on node node1: message 1")
              Log.expects(:error).with("Failure on node node2: message 2")

              result = task.log_results(results, 1)

              expect(result).to eq([false, "Failed Bolt run on 1 / 2 nodes in 1 seconds", results])

              results.delete(results.keys.find {|n| n.host == "node2"})
              result = task.log_results(results, 1)

              expect(result).to eq([true, "Successful Bolt run on 2 nodes in 1 seconds", results])
            end
          end

          describe "#run_task" do
            let(:taskrb) { File.expand_path("spec/fixtures/bolt/tasks/mymod/tasks/sample.rb") }

            it "should look for the path module if not given an existing dir" do
              task.from_hash("task" => "mymod::sample", "modules" => "spec/fixtures/bolt/tasks", "nodes" => ["rspec1", "rspec2"])
              executor.expects(:run_task).with(taskrb, "both", nil)
              task.run_task
            end

            it "should use the given path if its supplied and exist" do
              task.from_hash("task" => taskrb, "modules" => "spec/fixtures/bolt/tasks", "nodes" => ["rspec1", "rspec2"])
              task.expects(:bolt_cli).never
              executor.expects(:run_task).with(taskrb, "both", nil)
              task.run_task
            end
          end

          describe "#nodes" do
            it "should return as is for no transport or ssh transport" do
              task.from_hash("task" => "mymod::test", "modules" => "/nonexisting", "nodes" => ["rspec1", "rspec2"])

              nodes = task.nodes
              expect(nodes[0].uri).to eq("rspec1")
              expect(nodes[1].uri).to eq("rspec2")

              task.from_hash("task" => "mymod::test", "modules" => "/nonexisting", "nodes" => ["rspec1", "rspec2"], "transport" => "ssh")
              nodes = task.nodes
              expect(nodes[0].uri).to eq("rspec1")
              expect(nodes[1].uri).to eq("rspec2")
            end

            it "should convert to a uri for winrm transport" do
              task.from_hash("task" => "mymod::test", "modules" => "/nonexisting", "nodes" => ["rspec1", "rspec2"], "transport" => "winrm", "password" => "test")

              nodes = task.nodes
              expect(nodes[0].uri).to eq("winrm://rspec1")
              expect(nodes[1].uri).to eq("winrm://rspec2")
            end
          end

          describe "#validate_configuration!" do
            it "should validate required data" do
              task.from_hash({})
              expect { task.validate_configuration! }.to raise_error("Bolt requires one of task, plan or command")

              task.from_hash("task" => "mymod::test")
              expect { task.validate_configuration! }.to raise_error("A path to Bolt modules is required")

              task.from_hash("task" => "mymod::test", "modules" => "/some/dir")
              expect { task.validate_configuration! }.to raise_error("Bolt requires at least 1 node")

              task.from_hash("task" => "mymod::test", "modules" => "/nonexisting", "nodes" => ["rspec1", "rspec2"])
              expect { task.validate_configuration! }.to raise_error("The Bolt module path /nonexisting is not a directory")

              task.from_hash("task" => "mymod::test", "modules" => ".", "nodes" => ["rspec1", "rspec2"], "transport" => "fail")
              expect { task.validate_configuration! }.to raise_error("Transports can only be winrm or ssh")
            end
          end
        end
      end
    end
  end
end

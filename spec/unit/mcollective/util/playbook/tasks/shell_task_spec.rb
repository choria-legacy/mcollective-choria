require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      class Tasks
        describe ShellTask do
          let(:task) { ShellTask.new(stub) }

          describe "#to_execution_result" do
            it "should support success" do
              expect(task.to_execution_result([true, "Command completed successfully", ["stdout"]])).to eq(
                "localhost" => {
                  "value" => "stdout",
                  "type" => "shell",
                  "fail_ok" => false
                }
              )
            end

            it "should support errors" do
              task.from_hash("command" => "/tmp/x.sh")

              expect(task.to_execution_result([false, "Command failed with code 1", ["stdout"]])).to eq(
                "localhost" => {
                  "value" => "stdout",
                  "type" => "shell",
                  "fail_ok" => false,
                  "error" => {
                    "msg" => "Command failed with code 1",
                    "kind" => "choria.playbook/taskerror",
                    "details" => {
                      "command" => "/tmp/x.sh"
                    }
                  }
                }
              )
            end
          end

          describe "#run" do
            it "should detect failed scripts" do
              task.from_hash("command" => "/tmp/x.sh")
              Shell.expects(:new).with("/tmp/x.sh", "cwd" => Dir.pwd, "stdout" => [], "stderr" => []).returns(shell = stub)

              shell.expects(:runcommand)
              shell.stubs(:status).returns(stub(:exitstatus => 1))

              expect(task.run).to eq([false, "Command failed with code 1", []])
            end

            it "should detect successfull scripts" do
              task.from_hash("command" => "/tmp/x.sh")
              Shell.expects(:new).with("/tmp/x.sh", "cwd" => Dir.pwd, "stdout" => [], "stderr" => []).returns(shell = stub)

              shell.expects(:runcommand)
              shell.stubs(:status).returns(stub(:exitstatus => 0))

              expect(task.run).to eq([true, "Command completed successfully", []])
            end
          end

          describe "#shell_options" do
            it "should construct correct options" do
              task.from_hash(
                "command" => "/tmp/x.sh",
                "cwd" => "/tmp",
                "timeout" => 10,
                "environment" => {
                  "FOO" => "BAR"
                }
              )

              expect(task.shell_options).to eq(
                "cwd" => "/tmp",
                "timeout" => 10,
                "stdout" => [],
                "stderr" => [],
                "environment" => {
                  "FOO" => "BAR"
                }
              )
            end
          end

          describe "#validate_configuration!" do
            it "should expect a command" do
              expect { task.validate_configuration! }.to raise_error("A command was not given")
            end

            it "should validate nodes" do
              task.from_hash(
                "command" => "/tmp/x.sh",
                "nodes" => 1
              )
              expect { task.validate_configuration! }.to raise_error("Nodes were given but is not an array")
            end
          end

          describe "#from_hash" do
            it "should parse correctly" do
              task.from_hash(
                "command" => "/tmp/x.sh",
                "cwd" => "/tmp",
                "timeout" => 10,
                "environment" => {
                  "FOO" => "BAR"
                }
              )

              expect(task.instance_variable_get("@command")).to eq("/tmp/x.sh")
              expect(task.instance_variable_get("@cwd")).to eq("/tmp")
              expect(task.instance_variable_get("@timeout")).to eq(10)
              expect(task.instance_variable_get("@environment")).to eq(
                "FOO" => "BAR"
              )

              task.from_hash(
                "command" => "/tmp/x.sh",
                "nodes" => ["node1", "node2"]
              )

              expect(task.instance_variable_get("@command")).to eq("/tmp/x.sh --nodes node1,node2")
            end
          end
        end
      end
    end
  end
end

require "spec_helper"
require "mcollective/util/bolt_support"
require "puppet"

module MCollective
  module Util
    class BoltSupport
      describe TaskResult do
        let(:good_result) do
          {
            "good.example" => {
              "value" => "stdout",
              "type" => "shell",
              "fail_ok" => false
            }
          }
        end

        let(:error_result) do
          {
            "error.example" => {
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
          }
        end

        describe ".from_asserted_hash" do
          it "should load the correct data" do
            tr = TaskResult.from_asserted_hash(good_result)
            expect(tr.host).to eq("good.example")
            expect(tr.result).to eq(good_result["good.example"])
          end
        end

        describe "#error" do
          it "should be nil when not an error" do
            expect(TaskResult.from_asserted_hash(good_result).error).to be_nil
          end
        end

        describe "#ok" do
          it "should be true when fail_ok is true" do
            error_result["error.example"]["fail_ok"] = true
            tr = TaskResult.from_asserted_hash(error_result)
            expect(tr).to be_ok
          end

          it "should detect errors" do
            tr = TaskResult.from_asserted_hash(error_result)
            expect(tr).to_not be_ok
          end

          it "should detect non errors" do
            tr = TaskResult.from_asserted_hash(good_result)
            expect(tr).to be_ok
          end
        end

        describe "#[]" do
          it "should access the value data" do
            good_result["good.example"]["value"] = {"test" => "rspec"}
            tr = TaskResult.from_asserted_hash(good_result)
            expect(tr["test"]).to eq("rspec")
          end
        end

        describe "#type" do
          it "should get the correct type" do
            tr = TaskResult.from_asserted_hash(error_result)
            expect(tr.type).to eq("shell")
          end
        end
      end
    end
  end
end

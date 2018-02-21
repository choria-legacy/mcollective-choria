require "spec_helper"
require "mcollective/util/bolt_support"
require "puppet"

module MCollective
  module Util
    class BoltSupport
      describe TaskResults do
        let(:good_result) do
          TaskResult.new("good.example", "value" => "stdout", "type" => "shell", "fail_ok" => false)
        end

        let(:error_result) do
          TaskResult.new("error.example", "value" => "stdout",
                                          "type" => "shell",
                                          "fail_ok" => false,
                                          "error" => {
                                            "msg" => "Command failed with code 1",
                                            "kind" => "choria.playbook/taskerror",
                                            "details" => {
                                              "command" => "/tmp/x.sh"
                                            }
                                          })
        end

        describe "#.from_asserted_hash" do
          it "should load the correct data" do
            tr = TaskResults.from_asserted_hash([good_result, error_result])
            expect(tr.hosts).to eq(["good.example", "error.example"])
          end
        end

        describe "#count" do
          it "should count correctly" do
            tr = TaskResults.from_asserted_hash([good_result, error_result])
            expect(tr.count).to be(2)

            tr = TaskResults.from_asserted_hash({})
            expect(tr.count).to be(0)
          end
        end

        describe "#empty" do
          it "should support !epmty" do
            tr = TaskResults.from_asserted_hash([good_result, error_result])
            expect(tr).to_not be_empty
          end

          it "should support empty" do
            tr = TaskResults.from_asserted_hash({})
            expect(tr).to be_empty
          end
        end

        describe "#find" do
          it "should find the right node" do
            tr = TaskResults.from_asserted_hash([good_result, error_result])
            found = tr.find("error.example")
            expect(found).to be_a(TaskResult)
            expect(found.host).to eq("error.example")
          end
        end

        describe "#first" do
          it "should get the right result" do
            tr = TaskResults.from_asserted_hash([good_result, error_result])
            expect(tr.first.host).to eq("good.example")
          end
        end

        describe "#nodes" do
          it "should get the right nodes" do
            tr = TaskResults.from_asserted_hash([good_result, error_result])
            expect(tr.hosts).to eq(["good.example", "error.example"])
          end
        end

        describe "#ok" do
          it "should be true for all good replies" do
            tr = TaskResults.from_asserted_hash([good_result])
            expect(tr).to be_ok
          end

          it "should be false for some failures" do
            tr = TaskResults.from_asserted_hash([good_result, error_result])
            expect(tr).to_not be_ok
          end
        end
        describe "#each" do
          it "should loop each node" do
            tr = TaskResults.from_asserted_hash([good_result, error_result])

            seen = []
            tr.each {|r| seen << r.host}

            expect(seen).to eq(["good.example", "error.example"])
          end
        end
      end
    end
  end
end

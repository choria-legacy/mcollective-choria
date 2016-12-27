require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      class Tasks
        describe Mcollective_assertTask do
          let(:task) { Mcollective_assertTask.new }

          before(:each) do
            task.from_hash(
              "nodes" => ["node1", "node2"],
              "action" => "puppet.status",
              "pre_sleep" => 10,
              "description" => "test description",
              "expression" => [:idling, "==", true],
              "properties" => {"prop" => "rspec"}
            )
          end

          describe "#run" do
            it "should fail if the check fails" do
              task.stubs(:mcollective_task).returns(mct = stub)
              task.stubs(:perform_pre_sleep)
              mct.stubs(:run).returns([true, "ok", [{"data" => {:idling => true}, "sender" => "rspec1"}]])
              task.expects(:check_results).with([{"data" => {:idling => true}, "sender" => "rspec1"}]).returns([true, "rspec", []])

              expect(task.run).to eq([true, "rspec", []])
            end

            it "should fail if the run failed" do
              task.stubs(:mcollective_task).returns(mct = stub)

              seq = sequence(:s)
              task.expects(:perform_pre_sleep).in_sequence(seq)
              mct.expects(:run).in_sequence(seq).returns([false, "rspec", []])
              expect(task.run).to eq([false, "Request puppet.status failed: rspec", []])
            end
          end

          describe "#check_results" do
            it "should detect matching results" do
              results = [
                {"data" => {:idling => true}, "sender" => "rspec1"},
                {"data" => {:idling => true}, "sender" => "rspec2"}
              ]

              expect(task.check_results(results)).to eq([true, "All nodes matched expression idling == true", results])
            end

            it "should detect evaluation failed items" do
              Log.expects(:warn).with("Result from rspec2 does not match the expression")
              results = [
                {"data" => {:idling => true}, "sender" => "rspec1"},
                {"data" => {:idling => false}, "sender" => "rspec2"}
              ]

              expect(task.check_results(results)).to eq([false, "Not all nodes matched expression idling == true", results])
            end

            it "should detect missing data items" do
              Log.expects(:warn).with("Result from rspec1 does not have the idling item")
              Log.expects(:warn).with("Result from rspec2 does not have the idling item")
              task.expects(:evaluate).never

              results = [
                {"data" => {}, "sender" => "rspec1"},
                {"data" => {}, "sender" => "rspec2"}
              ]

              expect(task.check_results(results)).to eq([false, "Not all nodes matched expression idling == true", results])
            end
          end

          describe "#evaluate" do
            it "should support in" do
              expect(task.evaluate("foo", "in", ["foo", "bar"])).to be(true)
              expect(task.evaluate("foo", "in", ["bar", "bar"])).to be(false)
              expect(task.evaluate("foo", "!in", ["bar", "bar"])).to be(true)
            end

            it "should support =~" do
              expect(task.evaluate("foo", "=~", "o")).to be(true)
              expect(task.evaluate("FOO", "=~", "o")).to be(true)
              expect(task.evaluate("FOO", "=~", "a")).to be(false)
              expect(task.evaluate("foo", "=~", "a")).to be(false)
              expect(task.evaluate("foo", "!=~", "a")).to be(true)
            end

            it "should support ==" do
              expect(task.evaluate("1", "==", "1")).to be(true)
              expect(task.evaluate("1", "=", "1")).to be(true)
              expect(task.evaluate("1", "==", "2")).to be(false)
              expect(task.evaluate("1", "=", "2")).to be(false)
              expect(task.evaluate("1", "!=", "2")).to be(true)
              expect(task.evaluate("1", "!==", "2")).to be(true)
            end

            it "should support <" do
              [["a", "b"], [1, 2]].each do |left, right|
                expect(task.evaluate(left, "<", right)).to be(true)
              end

              [["b", "a"], [2, 1], [1, 1], ["a", "a"]].each do |left, right|
                expect(task.evaluate(left, "<", right)).to be(false)
              end

              expect(task.evaluate("a", "!<", "b")).to be(false)
            end

            it "should support >" do
              [["a", "b"], [1, 2], [1, 1], ["a", "a"]].each do |left, right|
                expect(task.evaluate(left, ">", right)).to be(false)
              end

              [["b", "a"], [2, 1]].each do |left, right|
                expect(task.evaluate(left, ">", right)).to be(true)
              end

              expect(task.evaluate("a", "!>", "b")).to be(true)
            end

            it "should support >=" do
              [["b", "a"], [2, 1]].each do |left, right|
                expect(task.evaluate(left, ">=", right)).to be(true)
              end

              [["a", "b"], [1, 2]].each do |left, right|
                expect(task.evaluate(left, ">=", right)).to be(false)
              end

              expect(task.evaluate("a", "!>=", "a")).to be(false)
            end

            it "should support <=" do
              [["b", "a"], [2, 1]].each do |left, right|
                expect(task.evaluate(left, "<=", right)).to be(false)
              end

              [["a", "b"], [1, 2], [1, 1], ["a", "a"]].each do |left, right|
                expect(task.evaluate(left, "<=", right)).to be(true)
              end

              expect(task.evaluate("a", "!<=", "a")).to be(false)
            end
          end

          describe "#mcollective_task" do
            it "should configure the task correctly" do
              Tasks::McollectiveTask.expects(:new).returns(mct = stub)

              mct.expects(:from_hash).with(
                "description" => "test description",
                "nodes" => ["node1", "node2"],
                "action" => "puppet.status",
                "properties" => {"prop" => "rspec"},
                "silent" => true
              )

              task.mcollective_task
            end
          end

          describe "#perform_pre_sleep" do
            it "should sleep once only" do
              task.from_hash("pre_sleep" => 1)
              task.expects(:sleep).with(1).once
              task.perform_pre_sleep
              task.perform_pre_sleep
              task.perform_pre_sleep
            end
          end

          describe "#validate_configuration!" do
            it "should detect invalid expressions" do
              task.from_hash("expression" => nil)
              expect { task.validate_configuration! }.to raise_error("An expression should be 3 items exactly")
            end
          end

          describe "#from_hash" do
            it "should hold correct values" do
              expect(task.instance_variable_get("@nodes")).to eq(["node1", "node2"])
              expect(task.instance_variable_get("@action")).to eq("puppet.status")
              expect(task.instance_variable_get("@pre_sleep")).to eq(10)
              expect(task.instance_variable_get("@expression")).to eq([:idling, "==", true])
              expect(task.instance_variable_get("@description")).to eq("test description")
            end
          end
        end
      end
    end
  end
end

require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      describe Tasks do
        let(:playbook) { Playbook.new }
        let(:tasks) { Tasks.new(playbook) }
        let(:task_list) { tasks.tasks }
        let(:playbook_fixture) { YAML.load(File.read("spec/fixtures/playbooks/playbook.yaml")) }

        before(:each) do
          tasks.from_hash(playbook_fixture["tasks"])
          tasks.from_hash(playbook_fixture["hooks"])
          Log.stubs(:error)
        end

        describe "#from_hash" do
          it "should support the 'tasks' list" do
            data = [{"rspec" => {}}]
            tasks.expects(:load_tasks).with(data, "tasks")
            expect(tasks.from_hash(data)).to be(tasks)
          end

          it "should support arbitrary lists" do
            data = {"rspec_list" => {"rspec" => {}}}
            tasks.expects(:load_tasks).with({"rspec" => {}}, "rspec_list")
            expect(tasks.from_hash(data)).to be(tasks)
          end
        end

        describe "#load_tasks" do
          let(:runner) { stub(:description= => nil, :description => "rspec description") }
          let(:result) { TaskResult.new }

          before(:each) do
            TaskResult.stubs(:new).returns(result)
          end

          it "should load the tasks and create a runner" do
            tasks.reset
            tasks.expects(:runner_for).with("rspec").returns(runner)
            tasks.load_tasks([{"rspec" => {}}], "tasks")
            expect(tasks.tasks["tasks"]).to eq(
              [
                :type => "rspec",
                :runner => runner,
                :description => "rspec description",
                :result => result,
                :properties => {
                  "tries" => 1,
                  "try_sleep" => 10,
                  "fail_ok" => false
                }
              ]
            )
          end

          it "should support overriding defaults" do
            tasks.reset
            tasks.expects(:runner_for).with("rspec").returns(runner)
            tasks.load_tasks([{"rspec" => {"tries" => 2, "try_sleep" => 5, "fail_ok" => true}}], "tasks")
            expect(tasks.tasks["tasks"].first).to include(
              :properties => {
                "tries" => 2,
                "try_sleep" => 5,
                "fail_ok" => true
              }
            )
          end
        end

        describe "#run" do
          let(:seq) { sequence(:seq) }

          it "should run the pre_book and fail if it fails" do
            tasks.expects(:run_set).with("pre_book").returns(false)
            tasks.expects(:run_set).with("tasks").never
            expect(tasks.run).to be(false)
          end

          it "should run the main tasks and on_success hook" do
            tasks.expects(:run_set).with("pre_book").returns(true).in_sequence(seq)
            tasks.expects(:run_set).with("tasks").returns(true).in_sequence(seq)
            tasks.expects(:run_set).with("on_success").returns(true).in_sequence(seq)
            tasks.expects(:run_set).with("post_book").returns(true).in_sequence(seq)
            expect(tasks.run).to be(true)
          end

          it "should run the main tasks and on_fail hook" do
            tasks.expects(:run_set).with("pre_book").returns(true).in_sequence(seq)
            tasks.expects(:run_set).with("tasks").returns(false).in_sequence(seq)
            tasks.expects(:run_set).with("on_fail").returns(true).in_sequence(seq)
            tasks.expects(:run_set).with("post_book").returns(true).in_sequence(seq)
            expect(tasks.run).to be(false)
          end

          it "on_success failure should fail the playbook" do
            tasks.expects(:run_set).with("pre_book").returns(true).in_sequence(seq)
            tasks.expects(:run_set).with("tasks").returns(true).in_sequence(seq)
            tasks.expects(:run_set).with("on_success").returns(false).in_sequence(seq)
            tasks.expects(:run_set).with("post_book").returns(true).in_sequence(seq)
            expect(tasks.run).to be(false)
          end

          it "post_book failure should fail the playbook" do
            tasks.expects(:run_set).with("pre_book").returns(true).in_sequence(seq)
            tasks.expects(:run_set).with("tasks").returns(true).in_sequence(seq)
            tasks.expects(:run_set).with("on_success").returns(true).in_sequence(seq)
            tasks.expects(:run_set).with("post_book").returns(false).in_sequence(seq)
            expect(tasks.run).to be(false)
          end
        end

        describe "#run_set" do
          it "should be true for empty sets" do
            tasks.expects(:run_task).never
            expect(tasks.run_set("on_fail")).to be(true)
          end

          it "should stop executing a set when the first failed task is met" do
            task_list["tasks"] << task_list["tasks"][0].clone
            tasks.expects(:run_task).with(task_list["tasks"][0], "tasks", true).returns(false)

            expect(tasks.run_set("tasks")).to be(false)
          end

          it "should return the right value" do
            task_list["tasks"] << task_list["tasks"][0].clone

            tasks.expects(:run_task).returns(true).twice
            expect(tasks.run_set("tasks")).to be(true)

            tasks.expects(:run_task).returns(true, false).twice
            expect(tasks.run_set("tasks")).to be(false)

            tasks.expects(:run_task).returns(false)
            expect(tasks.run_set("tasks")).to be(false)
          end
        end

        describe "#run_task" do
          let(:task) { task_list["tasks"][0] }

          before(:each) do
            tasks.stubs(:t).with(task[:properties]).returns(task[:properties])
            tasks.stubs(:t).with(task[:description]).returns(task[:description])
            tasks.stubs(:run_set).returns(true)
          end

          it "should run the pre_task and fail if it fails" do
            tasks.expects(:run_set).with("pre_task").returns(false)
            expect(tasks.run_task(task_list["tasks"][0], "tasks")).to be(false)
          end

          it "should support pre_sleeping" do
            task[:properties]["pre_sleep"] = 12
            tasks.expects(:sleep).with(12)
            task[:runner].expects(:run).returns([true, "pass 1", :x])
            task[:runner].stubs(:validate_configuration!)
            expect(tasks.run_task(task, "tasks")).to be(true)
          end

          it "should support retries" do
            task[:runner].expects(:run).twice.returns([false, "fail 1", :x], [false, "fail 2", :x])
            task[:runner].stubs(:validate_configuration!)
            tasks.expects(:sleep).with(20)

            expect(tasks.run_task(task, "tasks")).to be(false)
          end

          it "should run a task with retries just once if it passes" do
            task[:runner].expects(:run).returns([true, "pass 1", :x])
            task[:runner].stubs(:validate_configuration!)
            tasks.expects(:sleep).never

            expect(tasks.run_task(task, "tasks")).to be(true)
          end

          it "should support fail_ok" do
            task[:properties]["fail_ok"] = true
            task[:runner].expects(:run).returns([false, "fail 1", :x])
            task[:runner].stubs(:validate_configuration!)
            tasks.expects(:sleep).never

            expect(tasks.run_task(task, "tasks")).to be(true)
          end

          it "should support post_task hook and fail if it fails" do
            task[:runner].stubs(:run).returns([true, "pass 1", :x])
            task[:runner].stubs(:validate_configuration!)
            tasks.expects(:run_set).with("post_task").returns(true)
            expect(tasks.run_task(task, "tasks")).to be(true)

            tasks.expects(:run_set).with("post_task").returns(false)
            expect(tasks.run_task(task, "tasks")).to be(false)
          end

          it "should update the results" do
            task[:runner].expects(:run).returns([true, "pass 1", [:x]])
            task[:runner].stubs(:validate_configuration!)
            tasks.run_task(task_list["tasks"][0], "tasks")

            result = tasks.results.first
            expect(result.task).to be(task)
            expect(result.success).to be(true)
            expect(result.msg).to eq("pass 1")
            expect(result.data).to eq([:x])
          end
        end

        describe "#reset" do
          it "should reset tasks" do
            tasks.reset
            tasks.tasks.each_key {|key| expect(tasks.tasks[key]).to be_empty }
          end
        end
      end
    end
  end
end

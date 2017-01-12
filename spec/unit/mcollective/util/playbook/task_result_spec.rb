require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      describe TaskResult do
        let(:runner) { stub(:run => [true, "rspec", [:rspec]]) }
        let(:tr) { TaskResult.new(task) }
        let(:task) do
          {
            :description => "rspec task",
            :type => "rspec",
            :runner => runner,
            :properties => {}
          }
        end

        describe "#task_type" do
          it "should get the right type" do
            expect(tr.task_type).to eq("rspec")
          end
        end

        describe "#run_time" do
          it "should calculate the right elapsed time" do
            expect(tr.run_time).to eq(0)

            tr.instance_variable_set("@end_time", Time.now + 10)
            expect(tr.run_time).to be_within(0.1).of(10)
          end
        end

        describe "#timed_run" do
          it "should run and update properties" do
            expect(tr.ran).to be(false)

            tr.timed_run("rspec")

            expect(tr.task).to be(task)
            expect(tr.msg).to eq("rspec")
            expect(tr.data).to eq([:rspec])
            expect(tr.success).to be(true)
            expect(tr.ran).to be(true)
            expect(tr.set).to eq("rspec")
            expect(tr.description).to eq("rspec task")
          end

          it "should support fail_ok" do
            tr.timed_run("rspec")

            expect(tr.task).to be(task)
            expect(tr.msg).to eq("rspec")
            expect(tr.data).to eq([:rspec])
            expect(tr.success).to be(true)
          end

          it "should handle exceptions" do
            runner.stubs(:run).raises("rspec")
            tr.timed_run("rspec")

            expect(tr.task).to be(task)
            expect(tr.msg).to match(/Running task .+ failed unexpectedly: RuntimeError: rspec/)
            expect(tr.data.first).to be_a(RuntimeError)
            expect(tr.success).to be(false)
          end
        end

        describe "#success?" do
          it "should correctly report success" do
            expect(tr.success?).to be(false)
            tr.success = true
            expect(tr.success?).to be(true)
          end
        end
      end
    end
  end
end

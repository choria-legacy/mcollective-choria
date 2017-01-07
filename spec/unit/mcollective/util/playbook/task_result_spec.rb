require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      describe TaskResult do
        let(:tr) { TaskResult.new }

        describe "#run_time" do
          it "should calculate the right elapsed time" do
            expect(tr.run_time).to eq(0)

            tr.instance_variable_set("@end_time", Time.now + 10)
            expect(tr.run_time).to be_within(0.1).of(10)
          end
        end

        describe "#timed_run" do
          it "should run and update properties" do
            runner = stub(:run => [true, "rspec", [:rspec]])
            task = {:runner => runner}

            expect(tr.ran).to be(false)

            tr.timed_run(task)

            expect(tr.task).to be(task)
            expect(tr.msg).to eq("rspec")
            expect(tr.data).to eq([:rspec])
            expect(tr.success).to be(true)
            expect(tr.ran).to be(true)
          end

          it "should support fail_ok" do
            runner = stub(:run => [false, "rspec", [:rspec]])
            task = {:runner => runner, :properties => {"fail_ok" => true}}
            tr.timed_run(task)

            expect(tr.task).to be(task)
            expect(tr.msg).to eq("rspec")
            expect(tr.data).to eq([:rspec])
            expect(tr.success).to be(true)
          end

          it "should handle exceptions" do
            runner = stub
            runner.stubs(:run).raises("rspec")
            task = {:runner => runner}
            tr.timed_run(task)

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

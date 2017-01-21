require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      class Tasks
        describe DataTask do
          let(:ds) { stub }
          let(:playbook) { stub(:data_stores => ds) }
          let(:task) { DataTask.new(playbook) }

          describe "#run" do
            it "should support writing" do
              task.from_hash("action" => "write", "key" => "store/y", "value" => "x")
              ds.expects(:write).with("store/y", "x").returns("x")
              expect(task.run).to eq([true, "Wrote value to store/y", ["x"]])
            end

            it "should support deleting" do
              task.from_hash("action" => "delete", "key" => "store/y")
              ds.expects(:delete).with("store/y").returns("x")
              expect(task.run).to eq([true, "Deleted data item store/y", ["x"]])
            end

            it "should fail otherwise" do
              task.from_hash("action" => "foo", "key" => "store/y", "value" => "x")
              expect(task.run).to eq([false, "Unknown action foo", []])

              task.from_hash("action" => "delete", "key" => "store/y")
              ds.expects(:delete).raises("rspec error")
              expect(task.run).to eq([false, "Could not perform delete on data store/y: RuntimeError: rspec error", []])
            end
          end

          describe "#validate_configuration!" do
            it "should expect an action" do
              task.from_hash({})
              expect { task.validate_configuration! }.to raise_error("Action should be one of delete or write")

              task.from_hash("action" => "rspec")
              expect { task.validate_configuration! }.to raise_error("Action should be one of delete or write")
            end

            it "should expect a key" do
              task.from_hash("action" => "delete")
              expect { task.validate_configuration! }.to raise_error("A key to act on is needed")
            end

            it "should expect a value when writing" do
              task.from_hash("action" => "write", "key" => "x/y")
              expect { task.validate_configuration! }.to raise_error("A value is needed when writing")

              task.from_hash("action" => "delete", "key" => "x/y")
              task.validate_configuration!
            end
          end

          describe "#from_hash" do
            it "should store the properties" do
              task.from_hash(
                "action" => "write",
                "value" => "hello",
                "key" => "mem/x",
                "options" => {"overwrite" => true}
              )

              expect(task.key).to eq("mem/x")
              expect(task.action).to eq("write")
              expect(task.value).to eq("hello")
            end
          end
        end
      end
    end
  end
end

require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      class DataStores
        describe MemoryDataStore do
          let(:ds) { MemoryDataStore.new("rspec", stub) }
          let(:store) { ds.instance_variable_get("@store") }
          let(:locks) { ds.instance_variable_get("@locks") }

          describe "#prepare" do
            it "should clear the store and locks" do
              store["X"] = "y"
              locks["X"] = "y"
              ds.prepare

              expect(locks).to be_empty
              expect(store).to be_empty
            end
          end

          describe "#include?" do
            it "should find data correctly" do
              expect(ds.include?("rspec")).to be(false)
              ds.write("rspec", 1)
              expect(ds.include?("rspec")).to be(true)
            end
          end

          describe "#release" do
            it "should not fail unlocking an unlocked mutex" do
              ds.release("x")
            end

            it "should release the right lock" do
              ds.lock("x", 60, 60)
              expect(locks["x"]).to be_locked
              ds.release("x")
              expect(locks["x"]).to_not be_locked
            end
          end

          describe "#lock" do
            it "should create and lock the lock" do
              expect(locks).to eq({})
              ds.lock("x", 60, 60)
              expect(locks["x"]).to be_a(Mutex)
              expect(locks["x"]).to be_locked
            end
          end

          describe "#delete" do
            it "should delete the data" do
              store["x"] = "rsx"
              store["y"] = "rsy"
              ds.delete("x")
              expect(store).to eq("y" => "rsy")
            end
          end

          describe "#write" do
            it "should store the data" do
              ds.write("x", "rspec")
              expect(store["x"]).to eq("rspec")
            end
          end

          describe "#read" do
            it "should fail for unknown keys" do
              expect { ds.read("x") }.to raise_error("No such key x")
            end

            it "should read the right key cloned" do
              store["x"] = "rspec"
              expect(ds.read("x")).to_not be(store["x"])
              expect(ds.read("x")).to eq("rspec")
            end
          end
        end
      end
    end
  end
end

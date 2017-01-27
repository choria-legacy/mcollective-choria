require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      class DataStores
        describe EnvironmentDataStore do
          let(:ds) { EnvironmentDataStore.new("rspec", stub) }

          before(:each) do
            ds.from_hash({})
            ENV["RSPEC_TEST"] = "1"
          end

          describe "#key_for" do
            it "should not prefix by default" do
              expect(ds.key_for("RSPEC")).to eq("RSPEC")
              ds.from_hash("prefix" => "RSPEC_")
              expect(ds.key_for("RSPEC")).to eq("RSPEC_RSPEC")
              expect(ds.read("TEST")).to eq("1")
            end
          end

          describe "#include?" do
            it "should find data correctly" do
              expect(ds.include?("RSPEC_NONEXISTING")).to be(false)
              expect(ds.include?("RSPEC_TEST")).to be(true)
            end
          end

          describe "#delete" do
            it "should delete the data" do
              ds.delete("RSPEC_TEST")
              expect(ENV).to_not include("RSPEC_TEST")
            end
          end

          describe "#write" do
            it "should store the data" do
              ds.write("RSPEC_TEST", "rspec")
              expect(ENV["RSPEC_TEST"]).to eq("rspec")
            end
          end

          describe "#read" do
            it "should fail for unknown keys" do
              expect { ds.read("RSPEC_NONEXISTING") }.to raise_error("No such environment variable RSPEC_NONEXISTING")
            end

            it "should read the right key cloned" do
              expect(ds.read("RSPEC_TEST")).to eq("1")
            end
          end
        end
      end
    end
  end
end

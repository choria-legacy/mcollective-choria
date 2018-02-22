require "spec_helper"
require "mcollective/util/bolt_support"
require "puppet"

module MCollective
  module Util
    class BoltSupport
      describe PlanRunner do
        let(:tmpdir) { Dir.mktmpdir("rspec") }
        let(:runner) { PlanRunner.new("mymod::test", tmpdir, "spec/fixtures/bolt/plans", "err") }

        after(:each) do
          FileUtils.rm_rf(tmpdir)
        end

        describe "#facts" do
          it "should set the right facts" do
            expect(runner.facts).to eq("choria" => {"plan" => "mymod::test"})
          end
        end

        describe "#exist?" do
          it "should detect known plans" do
            expect(runner).to exist
          end

          it "should detect missing plans" do
            runner.instance_variable_set("@plan", "mymod::fail")
            expect(runner).to_not exist
          end
        end

        describe "#puppet_type_to_ruby" do
          it "should handle arrays" do
            expect(runner.puppet_type_to_ruby("Array[Integer]")).to eq([Numeric, true])
            expect(runner.puppet_type_to_ruby("Optional[Array[Integer]]")).to eq([Numeric, true])
          end

          it "should handle Integers" do
            expect(runner.puppet_type_to_ruby("Integer")).to eq([Numeric, false])
            expect(runner.puppet_type_to_ruby("Optional[Integer]")).to eq([Numeric, false])
          end

          it "should handle Floarunner" do
            expect(runner.puppet_type_to_ruby("Float")).to eq([Numeric, false])
            expect(runner.puppet_type_to_ruby("Optional[Float]")).to eq([Numeric, false])
          end

          it "should handle Hashes" do
            expect(runner.puppet_type_to_ruby("Hash")).to eq([Hash, false])
            expect(runner.puppet_type_to_ruby("Optional[Hash]")).to eq([Hash, false])
          end

          it "should handle Enums" do
            expect(runner.puppet_type_to_ruby("Enum[foo, bar]")).to eq([String, false])
            expect(runner.puppet_type_to_ruby("Optional[Enum[foo, bar]]")).to eq([String, false])
          end
        end
      end
    end
  end
end

require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      describe Inputs do
        let(:playbook) { stub }
        let(:inputs) { Inputs.new(playbook) }
        let(:playbook_fixture) { YAML.load(File.read("spec/fixtures/playbooks/playbook.yaml")) }

        describe "#keys" do
          it "should return the right keys" do
            inputs.from_hash(playbook_fixture["inputs"])
            expect(inputs.keys).to eq(["cluster", "two"])
          end
        end

        describe "#add_cli_options" do
          it "should add correct options" do
            app = stub
            input_def = {
              "string_input" => {"description" => "string input", "type" => "String", "default" => "1", "validation" => ":string"},
              "numeric_input" => {"description" => "numeric input", "type" => "Fixnum", "required" => true},
              "array_input" => {"description" => "array input", "type" => ":array"}
            }

            inputs.from_hash(input_def)

            app.class.expects(:option).with("string_input",
                                            :description => "string input (String) default: 1",
                                            :arguments => ["--string_input STRING_INPUT"],
                                            :type => String,
                                            :default => "1",
                                            :validation => ":string",
                                            :required => true)

            app.class.expects(:option).with("numeric_input",
                                            :description => "numeric input (Integer) ",
                                            :arguments => ["--numeric_input NUMERIC_INPUT"],
                                            :type => Integer,
                                            :default => nil,
                                            :validation => nil,
                                            :required => true)

            app.class.expects(:option).with("array_input",
                                            :description => "array input (:array) ",
                                            :arguments => ["--array_input ARRAY_INPUT"],
                                            :type => ":array",
                                            :default => nil,
                                            :validation => nil,
                                            :required => true)

            inputs.add_cli_options(app, true)
          end
        end

        describe "#prepare" do
          it "should validate each input, store it and validate requirements" do
            inputs.from_hash(playbook_fixture["inputs"])
            seq = sequence(:prep)

            inputs.expects(:validate_data).with("cluster", "beta").in_sequence(seq)
            inputs.expects(:validate_data).with("two", "foo").in_sequence(seq)
            inputs.expects(:validate_requirements).in_sequence(seq)

            inputs.prepare("cluster" => "beta", "two" => "foo")
            expect(inputs["two"]).to eq("foo")
          end
        end

        describe "#include?" do
          it "should detect inputs correctly" do
            inputs.from_hash(playbook_fixture["inputs"])
            expect(inputs.include?("cluster")).to eq(true)
            expect(inputs.include?("rspec")).to eq(false)
          end
        end

        describe "#[]" do
          it "should fail on invalid inputs" do
            expect {inputs["cluster"]}.to raise_error("Unknown input cluster")
          end

          it "should retrieve the right value" do
            inputs.from_hash(playbook_fixture["inputs"])
            expect(inputs["cluster"]).to eq("alpha")
          end
        end

        describe "#input_properties" do
          it "should retrieve the right properties" do
            inputs.from_hash(playbook_fixture["inputs"])

            expect(inputs.input_properties("cluster")).to include("description" => "Cluster to deploy")
          end
        end

        describe "#validate_requirements" do
          before(:each) do
            inputs.from_hash("has_req" => {"required" => true}, "does_not" => {"required" => false})
          end

          it "should detect missing requires" do
            expect {inputs.prepare({})}.to raise_error("Values were required but not given for inputs: has_req")
          end

          it "should detect all provided" do
            expect {inputs.prepare("has_req" => "given")}.to_not raise_error
          end
        end

        describe "#validate_data" do
          it "should support symbol like validators" do
            inputs.from_hash("test" => {"validation" => ":string"})
            Validator.expects(:validate).with("spec_value", :string)

            inputs.validate_data("test", "spec_value")
          end

          it "should support regex validators" do
            inputs.from_hash("test" => {"validation" => "/spec/"})
            Validator.expects(:validate).with("spec_value", Regexp.new(/spec/))

            inputs.validate_data("test", "spec_value")
          end

          it "should support other validators" do
            inputs.from_hash("test" => {"validation" => "1"})
            Validator.expects(:validate).with("spec_value", "1")

            inputs.validate_data("test", "spec_value")
          end

          it "should raise a new error on failure" do
            inputs.from_hash("test" => {"validation" => ":string"})

            expect do
              inputs.validate_data("test", 1)
            end.to raise_error("Failed to validate value for input test: value should be a string")
          end
        end

        describe "#from_hash" do
          it "should store the data" do
            inputs.from_hash(playbook_fixture["inputs"])
            expect(inputs.keys).to eq(["cluster", "two"])
          end

          it "should set the defaults" do
            inputs.from_hash("test" => {"default" => "test_default"})
            expect(inputs["test"]).to eq("test_default")
            expect(inputs.input_properties("test")["required"]).to be(true)
          end

          it "should not mangle supplied required status" do
            inputs.from_hash("test" => {"required" => false})
            expect(inputs.input_properties("test")["required"]).to be(false)
          end
        end
      end
    end
  end
end

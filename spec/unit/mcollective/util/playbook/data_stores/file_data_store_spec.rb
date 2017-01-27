require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      class DataStores
        describe FileDataStore do
          let(:ds) { FileDataStore.new("rspec", stub) }

          describe "#include?" do
            it "should find the right data" do
              ds.stubs(:data).returns("rspec" => "1")
              expect(ds.include?("rspec")).to be(true)
              expect(ds.include?("missing")).to be(false)
            end
          end

          describe "#delete" do
            it "should delete and save the data" do
              ds.stubs(:parse_data).returns("rspec" => "1", "new" => "2")
              ds.expects(:save_data).with("rspec" => "1")
              ds.delete("new")
            end
          end

          describe "#write" do
            it "should save the right data" do
              ds.stubs(:parse_data).returns("rspec" => "1")
              ds.expects(:save_data).with("rspec" => "1", "new" => "2")
              expect(ds.write("new", "2")).to eq("2")
            end
          end

          describe "#read" do
            it "should read the right data" do
              ds.stubs(:data).returns("rspec" => "1")
              expect(ds.read("rspec")).to eq("1")
              expect { ds.read("fail") }.to raise_error("No such key fail")
            end
          end

          describe "#save_data" do
            before(:each) do
              ds.file = "/nonexisting"
            end

            it "should support yaml" do
              File.expects(:open).with("/nonexisting", "w").yields(f = StringIO.new)
              ds.format = "yaml"
              ds.save_data("rspec" => "test")
              expect(YAML.load(f.string)).to eq("rspec" => "test")
            end

            it "should support json" do
              File.expects(:open).with("/nonexisting", "w").yields(f = StringIO.new)
              ds.format = "json"
              ds.save_data("rspec" => "test")
              expect(JSON.parse(f.string)).to eq("rspec" => "test")
            end
          end

          describe "#parse_data" do
            before(:each) do
              ds.file = "/nonexisting"
            end

            it "should return {} for empty files" do
              File.expects(:size).with("/nonexisting").returns(0)
              expect(ds.parse_data).to eq({})
            end

            it "should support json" do
              ds.format = "json"
              File.expects(:size).with("/nonexisting").returns(10)
              File.expects(:read).with("/nonexisting").returns('{"rspec":"bar"}')
              expect(ds.parse_data).to eq("rspec" => "bar")
            end

            it "should support yaml" do
              ds.format = "yaml"
              File.expects(:size).with("/nonexisting").returns(10)
              File.expects(:read).with("/nonexisting").returns("rspec: bar")
              expect(ds.parse_data).to eq("rspec" => "bar")
            end
          end

          describe "#data" do
            it "should return the parsed data" do
              ds.expects(:parse_data).returns("rspec" => true)
              expect(ds.data).to eq("rspec" => true)
            end
          end

          describe "#validate_configuration!" do
            it "should check for file" do
              ds.file = nil
              expect { ds.validate_configuration! }.to raise_error("No file given to use as data source")
            end

            it "should check for format" do
              ds.file = "/nonexisting"
              ds.format = nil
              expect { ds.validate_configuration! }.to raise_error("No file format given")
            end

            it "should check the file permissions" do
              ds.file = "/nonexisting"
              ds.format = "json"

              File.expects(:exist?).with("/nonexisting").returns(false)
              expect { ds.validate_configuration! }.to raise_error("Cannot find data file /nonexisting")

              File.expects(:exist?).with("/nonexisting").returns(true)
              File.expects(:readable?).with("/nonexisting").returns(false)
              expect { ds.validate_configuration! }.to raise_error("Cannot read data file /nonexisting")

              File.expects(:exist?).with("/nonexisting").returns(true)
              File.expects(:readable?).with("/nonexisting").returns(true)
              File.expects(:writable?).with("/nonexisting").returns(false)
              expect { ds.validate_configuration! }.to raise_error("Cannot write data file /nonexisting")

              File.expects(:exist?).with("/nonexisting").returns(true)
              File.expects(:readable?).with("/nonexisting").returns(true)
              File.expects(:writable?).with("/nonexisting").returns(true)
              ds.expects(:data).returns([])
              expect { ds.validate_configuration! }.to raise_error("The data file must contain a Hash or be empty")

              File.expects(:exist?).with("/nonexisting").returns(true)
              File.expects(:readable?).with("/nonexisting").returns(true)
              File.expects(:writable?).with("/nonexisting").returns(true)
              ds.expects(:data).returns({})
              ds.validate_configuration!
            end
          end
        end
      end
    end
  end
end

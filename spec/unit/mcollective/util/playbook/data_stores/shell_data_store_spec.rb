require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      class DataStores
        describe ShellDataStore do
          let(:ds) { ShellDataStore.new("rspec", stub) }
          let(:fixture) { File.expand_path("spec/fixtures/playbooks/shell_data.rb") }

          before(:each) do
            ds.from_hash("command" => fixture)
          end

          describe "#integration" do
            it "should produce correct commands" do
              expect { ds.read("x") }.to raise_error("Could not read key x, got exitcode 1")
              ds.write("x", "y")
              expect(ds.read("x")).to eq("y")
              ds.delete("x")
              expect { ds.read("x") }.to raise_error("Could not read key x, got exitcode 1")
            end
          end

          describe "#shell_options" do
            it "should return the right options" do
              expect(ds.shell_options).to eq("timeout" => 10, "environment" => {})
            end

            it "should return the right options with all settings set" do
              ds.from_hash("cwd" => "/nonexisting_cwd", "environment" => {"rspec" => "1"}, "timeout" => 20)
              expect(ds.shell_options).to eq("timeout" => 20, "environment" => {"rspec" => "1"}, "cwd" => "/nonexisting_cwd")
            end
          end

          describe "#validate_configuration!" do
            it "should validate the command" do
              ds.from_hash({})
              expect { ds.validate_configuration! }.to raise_error("A command is required")

              ds.from_hash("command" => "/nonexisting")
              expect { ds.validate_configuration! }.to raise_error("Command /nonexisting is not executable")
            end

            it "should validate the timeout" do
              File.stubs(:executable?).with("/nonexisting").returns(true)

              ds.from_hash("command" => "/nonexisting", "timeout" => "a")
              expect { ds.validate_configuration! }.to raise_error("Timeout should be an integer")
            end

            it "should validate the environment" do
              File.stubs(:executable?).with("/nonexisting").returns(true)

              ds.from_hash("command" => "/nonexisting", "environment" => 1)
              expect { ds.validate_configuration! }.to raise_error("Environment should be a hash")

              ds.from_hash("command" => "/nonexisting", "environment" => {1 => 1})
              expect { ds.validate_configuration! }.to raise_error("All keys and values in the environment must be strings")

              ds.from_hash("command" => "/nonexisting", "environment" => {"a" => 1})
              expect { ds.validate_configuration! }.to raise_error("All keys and values in the environment must be strings")

              ds.from_hash("command" => "/nonexisting", "environment" => {1 => "a"})
              expect { ds.validate_configuration! }.to raise_error("All keys and values in the environment must be strings")
            end

            it "should validate the cwd" do
              File.stubs(:executable?).with("/nonexisting").returns(true)

              ds.from_hash("command" => "/nonexisting", "cwd" => "/nonexisting_cwd")
              expect { ds.validate_configuration! }.to raise_error("cwd /nonexisting_cwd does not exist")

              ds.from_hash("command" => "/nonexisting", "cwd" => "/nonexisting_cwd")
              File.stubs(:exist?).returns(true)
              expect { ds.validate_configuration! }.to raise_error("cwd /nonexisting_cwd is not a directory")
            end

            it "should accept valid configs" do
              expect(ds.validate_configuration!).to be_nil
            end
          end

          describe "#from_hash" do
            it "should set sane defaults" do
              expect(ds.timeout).to be(10)
              expect(ds.environment).to eq({})
              expect(ds.cwd).to be_nil
            end

            it "should accept supplied values" do
              ds.from_hash("command" => fixture, "timeout" => 20, "environment" => {"rspec" => 1}, "cwd" => "/nonexisting")
              expect(ds.command).to eq(File.expand_path("spec/fixtures/playbooks/shell_data.rb"))
              expect(ds.timeout).to be(20)
              expect(ds.environment).to eq("rspec" => 1)
              expect(ds.cwd).to eq("/nonexisting")
            end
          end

          describe "#validate_key" do
            it "should not accept invalid keys" do
              expect { ds.validate_key("foo|bar") }.to raise_error("Valid keys must match ^[a-zA-Z0-9_-]+$")
            end

            it "should accept valid keys" do
              %w[foo_bar FOO_BAR FOO_bar 1FOO_bar FOO_bar1 1FOO1bar1].each do |test|
                expect(ds.validate_key(test)).to be(true)
              end
            end
          end

          describe "#run_command" do
            it "should create and run a shell" do
              Shell.expects(:new).with("/nonexisting/command", "stdin" => "rspec").returns(s = stub)
              s.expects(:runcommand)
              expect(ds.run_command("/nonexisting/command", "stdin" => "rspec")).to be(s)
            end
          end

          describe "#run" do
            it "should only accept valid keys" do
              expect { ds.run("read", "foo|bar") }.to raise_error("Valid keys must match ^[a-zA-Z0-9_-]+$")
            end

            it "should support a supplied environment" do
              ds.expects(:run_command).with("#{fixture} --write",
                                            "timeout" => 10,
                                            "environment" => {
                                              "CHORIA_DATA_VALUE" => "hello world",
                                              "CHORIA_DATA_KEY" => "rspec_test",
                                              "CHORIA_DATA_ACTION" => "write"
                                            }).returns(stub(:status => stub(:exitstatus => 0)))

              ds.write("rspec_test", "hello world")
            end

            it "should detect command failures" do
              expect { ds.run("read", "force_fail") }.to raise_error("Could not read key force_fail, got exitcode 1")
            end
          end

          describe "#read" do
            it "should read the key correctly" do
              ds.expects(:run).with("read", "rspec_key").returns(stub(:stdout => "rspec_data"))
              expect(ds.read("rspec_key")).to eq("rspec_data")
            end
          end

          describe "#write" do
            it "should write the key correctly" do
              ds.expects(:run).with("write", "rspec_key", "CHORIA_DATA_VALUE" => "rspec value")
              expect(ds.write("rspec_key", "rspec value")).to be_nil
            end
          end

          describe "#delete" do
            it "should delete the key correctly" do
              ds.expects(:run).with("delete", "rspec_key")
              expect(ds.delete("rspec_key")).to be_nil
            end
          end
        end
      end
    end
  end
end

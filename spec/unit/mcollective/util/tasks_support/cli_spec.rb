require "spec_helper"
require "mcollective/util/choria"
require "mcollective/util/tasks_support"
require "mcollective/util/tasks_support/cli"

module MCollective
  module Util
    class TasksSupport
      describe CLI do
        let(:choria) { Choria.new(false) }
        let(:ts) { TasksSupport.new(choria, "/tmp") }
        let(:cli) { ts.cli(:console, true) }
        let(:task_fixture) { JSON.parse(File.read("spec/fixtures/tasks/tasks_list.json")) }

        describe "#transform_hash_strings" do
          it "should transform a json string to hash if the input is a hash" do
            inputs = {
              "params" => '{"message":"hello world"}'
            }

            meta = {
              "metadata" => {
                "parameters" => {
                  "params" => {
                    "description" => "A map of parameter names and values to apply",
                    "type" => "Optional[Hash[String[1], Data]]"
                  }
                }
              }
            }

            cli.transform_hash_strings(meta, inputs)

            expect(inputs["params"]).to eq("message" => "hello world")
          end
        end

        describe "#task_metadata" do
          it "should fetch and cache the metadata" do
            fixture = JSON.parse(File.read("spec/fixtures/tasks/puppet_conf_metadata.json"))
            ts.expects(:task_metadata).with("puppet_conf", "rspec").returns(fixture).once

            expect(cli.task_metadata("puppet_conf", "rspec")).to eq(fixture)
            expect(cli.task_metadata("puppet_conf", "rspec")).to eq(fixture)
          end
        end

        describe "#task_input" do
          it "should use the input as JSON by default" do
            configuration = {:__json_input => '{"name":"rspec"}'}
            expect(cli.task_input(configuration)).to eq("name" => "rspec")
          end

          it "should support json files" do
            configuration = {:__json_input => "@spec/fixtures/tasks/json_input.json"}
            expect(cli.task_input(configuration)).to eq("name" => "json_input_fixture")
          end

          it "should support yaml files" do
            configuration = {:__json_input => "@spec/fixtures/tasks/json_input.yaml"}
            expect(cli.task_input(configuration)).to eq("name" => "yaml_input_fixture")
          end

          it "should merge given options" do
            configuration = {
              :name => "cli override",
              :__json_input => "@spec/fixtures/tasks/json_input.yaml"
            }
            expect(cli.task_input(configuration)).to eq("name" => "cli override")
          end

          it "should not fail when there are no inputs" do
            expect(cli.task_input({})).to eq({})
          end
        end

        describe "#show_task_help" do
          it "should show the right help" do
            cli.expects(:task_metadata).with("puppet_conf", "rspec").returns(
              JSON.parse(File.read("spec/fixtures/tasks/puppet_conf_metadata.json"))
            )

            out = StringIO.new
            cli.show_task_help("puppet_conf", "rspec", out)

            expect(out.string).to include("  action                         The operation (get, set) to perform on the configuration setting (Enum[get, set])")
            expect(out.string).to include("  init.rb                        1231 bytes")
            expect(out.string).to include("Use 'mco tasks run puppet_conf' to run this task")
          end
        end

        describe "#task_list" do
          it "should support fetching just the names" do
            out = StringIO.new

            ts.expects(:tasks).with("rspec").returns(task_fixture)
            expect(cli.task_list("rspec", false, out)).to eq(
              "choria::ls" => "",
              "puppet_conf" => ""
            )
          end

          it "should support fetching detail" do
            out = StringIO.new

            ts.expects(:tasks).with("rspec").returns(task_fixture)
            cli.expects(:task_metadata).with("choria::ls", "rspec").returns(
              JSON.parse(File.read("spec/fixtures/tasks/choria_ls_metadata.json"))
            )

            cli.expects(:task_metadata).with("puppet_conf", "rspec").returns(
              JSON.parse(File.read("spec/fixtures/tasks/puppet_conf_metadata.json"))
            )

            expect(cli.task_list("rspec", true, out)).to eq(
              "choria::ls" => "Get directory contents",
              "puppet_conf" => "Inspect puppet agent configuration settings"
            )
          end
        end

        describe "#show_task_list" do
          before(:each) do
            cli.expects(:task_list).returns(
              "choria:task_1" => "task 1 description",
              "choria:task_with_long_name" => "long task description",
              "choria:task_2" => "task 2 description",
              "choria:task_3" => "task 3 description",
              "choria:task_4" => "task 4 description",
              "choria:task_5" => "task 5 description"
            )
          end

          it "should show just the task names by default" do
            out = StringIO.new
            cli.show_task_list("production", false, out)
            expect(out.string).to include("  choria:task_1                choria:task_with_long_name   choria:task_2")
            expect(out.string).to include("  choria:task_3                choria:task_4                choria:task_5")
          end

          it "should support task details" do
            out = StringIO.new
            cli.show_task_list("production", true, out)

            expect(out.string).to include("  choria:task_1                task 1 description")
            expect(out.string).to include("  choria:task_with_long_name   long task description")
            expect(out.string).to include("  choria:task_5                task 5 description")
          end
        end

        describe "#initialize" do
          it "should set the json formatter" do
            expect(CLI.new(ts, :json, false).output).to be_a(CLI::JSONFormatter)
          end

          it "should set the default formatter" do
            expect(CLI.new(ts, :other, false).output).to be_a(CLI::DefaultFormatter)
          end
        end
      end
    end
  end
end

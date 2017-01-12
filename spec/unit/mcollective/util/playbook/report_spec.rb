require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      describe Report do
        let(:playbook) { Playbook.new }
        let(:nodes) { playbook.instance_variable_get("@nodes") }
        let(:tasks) { playbook.instance_variable_get("@tasks") }
        let(:uses) { playbook.instance_variable_get("@uses") }
        let(:inputs) { playbook.instance_variable_get("@inputs") }
        let(:report) { playbook.report }
        let(:playbook_fixture) { YAML.load(File.read("spec/fixtures/playbooks/playbook.yaml")) }
        let(:results) do
          [
            stub(
              :task_type => "rspec_type1",
              :set => "rspec_set1",
              :description => "rspec test1",
              :start_time => Time.at(1484245208),
              :end_time => Time.at(1484245209),
              :run_time => 1.0,
              :ran => true,
              :msg => "rspec message",
              :success => true
            ),
            stub(
              :task_type => "rspec_type2",
              :set => "rspec_set2",
              :description => "rspec test2",
              :start_time => Time.at(1484245210),
              :end_time => Time.at(1484245212),
              :run_time => 2.0,
              :ran => true,
              :msg => "rspec message",
              :success => false
            )
          ]
        end

        before(:each) do
          playbook.from_hash(playbook_fixture)
          playbook.stubs(:task_results).returns(results)
        end

        describe "#finalize" do
          it "should fetch all data and produce a report" do
            report.expects(:store_playbook_metadata)
            report.expects(:store_static_inputs)
            report.expects(:store_node_groups)
            report.expects(:store_task_results)
            report.expects(:calculate_metrics)
            report.expects(:to_report)

            report.finalize(false, "rspec message")

            expect(report.instance_variable_get("@success")).to be(false)
            expect(report.instance_variable_get("@fail_message")).to eq("rspec message")
          end
        end

        describe "#calculate_metrics" do
          it "should calculate the right metrics" do
            report.store_task_results
            metrics = report.calculate_metrics

            expect(metrics).to include(
              "task_count" => 2,
              "task_types" => {
                "rspec_type1" => {
                  "count" => 1,
                  "total_time" => 1.0,
                  "pass" => 1,
                  "fail" => 0
                },
                "rspec_type2" => {
                  "count" => 1,
                  "total_time" => 2.0,
                  "pass" => 0,
                  "fail" => 1
                }
              }
            )
          end
        end

        describe "#store_task_results" do
          it "should store the right result data" do
            tasks = report.store_task_results
            expect(tasks).to eq(
              [
                {
                  "type" => "rspec_type1",
                  "set" => "rspec_set1",
                  "description" => "rspec test1",
                  "start_time" => Time.at(1484245208).utc,
                  "end_time" => Time.at(1484245209).utc,
                  "run_time" => 1.0,
                  "ran" => true,
                  "msg" => "rspec message",
                  "success" => true
                },
                {
                  "type" => "rspec_type2",
                  "set" => "rspec_set2",
                  "description" => "rspec test2",
                  "start_time" => Time.at(1484245210).utc,
                  "end_time" => Time.at(1484245212).utc,
                  "run_time" => 2.0,
                  "ran" => true,
                  "msg" => "rspec message",
                  "success" => false
                }
              ]
            )
          end
        end

        describe "#store_playbook_metadata" do
          it "should store the right data" do
            report.store_playbook_metadata
            expect(report.instance_variable_get("@playbook_name")).to eq("test_playbook")
            expect(report.instance_variable_get("@playbook_version")).to eq("1.1.2")
          end
        end

        describe "#store_node_groups" do
          it "should fetch all the node sets" do
            nodes.stubs(:keys).returns(["nodes1", "nodes2"])
            nodes.stubs(:[]).with("nodes1").returns(["node1.1", "node1.2"])
            nodes.stubs(:[]).with("nodes2").returns(["node2.1", "node2.2"])

            report.store_node_groups
            expect(report.instance_variable_get("@nodes")).to eq(
              "nodes1" => ["node1.1", "node1.2"],
              "nodes2" => ["node2.1", "node2.2"]
            )
          end
        end

        describe "#store_static_inputs" do
          it "should fetch all the inputs" do
            inputs.prepare(
              "cluster" => "alpha",
              "two" => "2"
            )

            report.store_static_inputs

            expect(report.instance_variable_get("@inputs")["static"]).to eq(
              "cluster" => "alpha",
              "two" => "2"
            )
          end
        end

        describe "#append_log" do
          it "should append the log correctly" do
            report.append_log(t = Time.now, :debug, "x:1:1", "rspec test")
            expect(report.instance_variable_get("@logs")[0]).to eq(
              "time" => t.utc.to_i,
              "level" => "debug",
              "from" => "x:1:1",
              "msg" => "rspec test"
            )
          end
        end
      end
    end
  end
end

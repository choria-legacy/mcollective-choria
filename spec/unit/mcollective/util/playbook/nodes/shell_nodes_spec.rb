require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      class Nodes
        describe ShellNodes do
          let(:nodes) { ShellNodes.new }
          let(:bad_fixture) { File.expand_path("spec/fixtures/playbooks/nodes.yaml") }
          let(:fixture) { File.expand_path("spec/fixtures/playbooks/script_nodes.sh") }
          let(:corrupt_fixture) { File.expand_path("spec/fixtures/playbooks/bad_script_nodes.sh") }

          describe "#validate_configuration!" do
            it "should allow good scenarios" do
              nodes.from_hash("script" => fixture)
              nodes.validate_configuration!
            end

            it "should detect no script set" do
              expect { nodes.validate_configuration! }.to raise_error("No node source script specified")
            end

            it "should detect scripts that are not executable" do
              nodes.from_hash("script" => bad_fixture)
              expect { nodes.validate_configuration! }.to raise_error("Node source script is not executable")
            end

            it "should detect scripts that return no data" do
              nodes.from_hash("script" => fixture)
              nodes.expects(:data).returns([])
              expect { nodes.validate_configuration! }.to raise_error("Node source script produced no results")
            end
          end

          describe "#from_hash" do
            it "should record the script path" do
              nodes.from_hash("script" => fixture)
              expect(nodes.instance_variable_get("@script")).to eq(fixture)
            end
          end

          describe "#valid_hostname?" do
            it "should correctly detect certnames" do
              expect(nodes.valid_hostname?("example.net")).to be_truthy
              expect(nodes.valid_hostname?("node1 example.net")).to be_falsey
            end
          end

          describe "#data" do
            it "should detect corrupt data" do
              nodes.from_hash("script" => corrupt_fixture)
              expect { nodes.data }.to raise_error("node1 example.net is not a valid hostname")
            end

            it "should only accept outputs that exit with status 0" do
              nodes.from_hash("script" => "echo 'example.net';exit 0")
              expect(nodes.data).to eq(["example.net"])

              nodes.from_hash("script" => "echo 'example.net';exit 1")
              expect { nodes.data }.to raise_error("Could not discover nodes via shell method, command exited with code 1")
            end
          end

          describe "#discover" do
            it "should find all the nodes" do
              nodes.from_hash("script" => fixture)
              expect(nodes.discover).to eq(["node1.example.net", "node2.example.net"])
            end
          end
        end
      end
    end
  end
end

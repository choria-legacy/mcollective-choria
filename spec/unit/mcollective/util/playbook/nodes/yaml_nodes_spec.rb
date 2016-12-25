require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      class Nodes
        describe YamlNodes do
          let(:nodes) { YamlNodes.new }
          let(:fixture) { File.expand_path("spec/fixtures/playbooks/nodes.yaml") }

          describe "#discover" do
            it "should discover the right nodes" do
              nodes.from_hash("group" => "uk", "source" => fixture)
              expect(nodes.discover).to eq(["node1.example.net", "node2.example.net", "node3.example.net"])
            end
          end

          describe "#data" do
            it "should read and cache the file" do
              nodes.from_hash("group" => "uk", "source" => fixture)
              data = YAML.load(File.read(fixture))

              expect(found = nodes.data).to eq(data)
              expect(nodes.data).to be(found)
            end
          end

          describe "#validate_configuration!" do
            it "should detect good setups" do
              nodes.from_hash("group" => "uk", "source" => fixture)
              nodes.validate_configuration!
            end

            it "should detect no file set" do
              expect { nodes.validate_configuration! }.to raise_error("No node group YAML source file specified")
            end

            it "should detect unreadable files" do
              nodes.from_hash("source" => "/nonexisting")
              expect { nodes.validate_configuration! }.to raise_error("Node group YAML source file /nonexisting is not readable")
            end

            it "should detect no group set" do
              nodes.from_hash("source" => fixture)
              expect { nodes.validate_configuration! }.to raise_error("No node group name specified")
            end

            it "should detect missing groups" do
              nodes.from_hash("group" => "fr", "source" => fixture)
              expect { nodes.validate_configuration! }.to raise_error("No data group fr defined in the data file %s" % fixture)
            end

            it "should detect non array data" do
              nodes.from_hash("group" => "non_array", "source" => fixture)
              expect { nodes.validate_configuration! }.to raise_error("Data group non_array is not an array")
            end

            it "should detect empty sets" do
              nodes.from_hash("group" => "empty_array", "source" => fixture)
              expect { nodes.validate_configuration! }.to raise_error("Data group empty_array is empty")
            end
          end

          describe "#from_hash" do
            it "should save the group and source" do
              nodes.from_hash("group" => "uk", "source" => fixture)
              expect(nodes.instance_variable_get("@group")).to eq("uk")
              expect(nodes.instance_variable_get("@file")).to eq(fixture)
            end
          end
        end
      end
    end
  end
end

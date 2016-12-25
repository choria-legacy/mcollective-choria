require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      describe Nodes do
        let(:playbook) { Playbook.new }
        let(:nodes) { Nodes.new(playbook) }
        let(:playbook_fixture) { YAML.load(File.read("spec/fixtures/playbooks/playbook.yaml")) }

        describe "#resolver_for" do
          it "should get the right resolver" do
            expect(nodes.resolver_for("mcollective")).to be_a(Nodes::McollectiveNodes)
            expect(nodes.resolver_for("pql")).to be_a(Nodes::PqlNodes)

            expect { nodes.resolver_for("rspec") }.to raise_error("Cannot find a handler for Node Set type rspec")
          end
        end

        describe "#from_hash" do
          it "should set up resolvers for each node set" do
            resolver = stub
            nodes.expects(:resolver_for).with("mcollective").returns(resolver)

            resolver.expects(:from_hash).with("type" => "mcollective")
            resolver.expects(:validate_configuration!)

            nodes.from_hash("rspec" => {"type" => "mcollective"})

            expect(nodes.nodes["rspec"][:resolver]).to be(resolver)
          end
        end

        describe "#limit_nodes" do
          it "should limit nodes" do
            nodes.from_hash(playbook_fixture["nodes"])
            nodes.nodes["load_balancers"][:discovered] = ["r1", "r2", "r3"]
            nodes.limit_nodes("load_balancers")
            expect(nodes["load_balancers"]).to eq(["r1"])
          end
        end

        describe "check_empty" do
          it "should raise the when_empty message if set" do
            nodes.from_hash(playbook_fixture["nodes"])
            expect { nodes.check_empty("load_balancers") }.to raise_error("No load balancers found with class haproxy")
          end

          it "should have a default message" do
            nodes.from_hash(playbook_fixture["nodes"])
            expect { nodes.check_empty("web_servers") }.to raise_error("Did not discover any nodes for nodeset web_servers")
          end

          it "should not raise for found nodes" do
            nodes.expects(:[]).returns(["rspec1"])
            nodes.check_empty("rspec")
          end
        end

        describe "#validate_nodes" do
          it "should correctly validate nodes" do
            nodes.from_hash(playbook_fixture["nodes"])

            expect { nodes.validate_nodes("web_servers") }.to raise_error("Node set web_servers needs at least 2 nodes, got 0")

            nodes.nodes["web_servers"][:discovered] = ["r1"]
            expect { nodes.validate_nodes("web_servers") }.to raise_error("Node set web_servers needs at least 2 nodes, got 1")

            nodes.nodes["web_servers"][:discovered] = ["r1", "r2", "r3"]
            expect(nodes.validate_nodes("web_servers"))
          end
        end

        describe "test_nodes" do
          it "should test all the elegible hosts" do
            nodeset = {
              "one" => playbook_fixture["nodes"]["load_balancers"].clone,
              "two" => playbook_fixture["nodes"]["load_balancers"].clone
            }
            nodeset["one"]["test"] = false
            nodeset["two"]["test"] = true

            nodes.from_hash(nodeset)
            nodes.nodes["one"][:discovered] = ["one_1", "one_2"]
            nodes.nodes["two"][:discovered] = ["two_1", "two_2"]

            task = stub
            task.expects(:from_hash).with(
              "nodes" => ["two_1", "two_2"],
              "action" => "rpcutil.ping",
              "silent" => true
            ).twice

            nodes.stubs(:mcollective_task).returns(task)

            task.expects(:run).returns([true, "success", ""])
            nodes.test_nodes

            task.expects(:run).returns([false, "rspec fail", ""])
            expect { nodes.test_nodes }.to raise_error("Connectivity test failed for some nodes: rspec fail")
          end
        end

        describe "#should test?" do
          it "should correctly determine if nodes need testing" do
            nodes.from_hash(playbook_fixture["nodes"])

            expect(nodes.should_test?("load_balancers")).to be(true)

            nodes.properties("load_balancers")["test"] = false
            expect(nodes.should_test?("load_balancers")).to be(false)
          end
        end

        describe "#check_uses" do
          it "should validate all the agents" do
            nodes.from_hash(playbook_fixture["nodes"])
            nodes.nodes["load_balancers"][:discovered] = ["rspec1", "rspec2"]

            playbook.expects(:validate_agents).with(
              "rpcutil" => ["rspec1", "rspec2"],
              "puppet" => ["rspec1", "rspec2"]
            )

            nodes.check_uses
          end
        end

        describe "#resolve_nodes" do
          it "should prepare and discover" do
            nodes.from_hash(playbook_fixture["nodes"])
            seq = sequence(:nodes)
            resolver = nodes.nodes["load_balancers"][:resolver]
            resolver.expects(:prepare).in_sequence(seq)
            resolver.expects(:discover).in_sequence(seq).returns(["rspec1", "rspec2"])

            nodes.resolve_nodes("load_balancers")

            expect(nodes["load_balancers"]).to eq(["rspec1", "rspec2"])
          end
        end

        describe "#prepare" do
          it "should resolve and validate node sets" do
            nodes.from_hash(playbook_fixture["nodes"])
            seq = sequence(:nodes)

            ["load_balancers", "web_servers"].each do |set|
              nodes.expects(:resolve_nodes).with(set).in_sequence(seq)
              nodes.expects(:check_empty).with(set).in_sequence(seq)
              nodes.expects(:limit_nodes).with(set).in_sequence(seq)
              nodes.expects(:validate_nodes).with(set).in_sequence(seq)
            end

            nodes.expects(:test_nodes).in_sequence(seq)
            nodes.expects(:check_uses).in_sequence(seq)

            nodes.prepare
          end
        end

        describe "#include?" do
          it "should correctly detect nodesets" do
            nodes.from_hash(playbook_fixture["nodes"])
            expect(nodes.include?("load_balancers")).to be(true)
            expect(nodes.include?("rspec")).to be(false)
          end
        end

        describe "#properties" do
          it "should get the right properties" do
            nodes.from_hash(playbook_fixture["nodes"])
            expect(nodes.properties("load_balancers")).to eq(playbook_fixture["nodes"]["load_balancers"])
          end

          it "should fail for unknown nodes" do
            expect { nodes.properties("rspec") }.to raise_error("Unknown node set rspec")
          end
        end

        describe "#[]" do
          it "should get the right nodes" do
            nodes.from_hash(playbook_fixture["nodes"])
            nodes.nodes["load_balancers"][:discovered] = ["rspec"]
            expect(nodes["load_balancers"]).to eq(["rspec"])
          end

          it "should fail for unknown nodes" do
            expect { nodes["rspec"] }.to raise_error("Unknown node set rspec")
          end
        end

        describe "#keys" do
          it "should return the right keys" do
            nodes.from_hash(playbook_fixture["nodes"])
            expect(nodes.keys).to eq(["load_balancers", "web_servers"])
          end
        end
      end
    end
  end
end

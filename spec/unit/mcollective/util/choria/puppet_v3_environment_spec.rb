require "spec_helper"
require "mcollective/util/choria"

module MCollective
  module Util
    class Choria
      describe PuppetV3Environment do
        let(:site) { JSON.parse(File.read("spec/fixtures/sample_app.json")) }
        let(:env) { PuppetV3Environment.new(site) }

        describe "#has_runable_nodes?" do
          it "should detect cyclic catalogs" do
            expect {
              PuppetV3Environment.new(JSON.parse(File.read("spec/fixtures/cyclic_app.json")))
            }.to raise_error("Impossible to resolve site catalog found, cannot continue with any instances")
          end
        end

        describe "#valid_application" do
          it "should correctly check apps" do
            expect(env.valid_application?("Lamp[app1]")).to be_truthy
            expect(env.valid_application?("Lamp[app3]")).to be_falsey
          end
        end

        describe "#satisfy_dependencies!" do
          it "should satisfy the dependencies" do
            nv = env.node_view

            expect(nv["dev2.devco.net"][:consumes]).to eq(["Sql[app2]", "Sql[app1]"])
            expect(nv["dev3.devco.net"][:consumes]).to eq(["Sql[app2]", "Sql[app1]"])
            expect(nv["dev4.devco.net"][:consumes]).to eq(["Sql[app2]", "Sql[app1]"])

            env.satisfy_dependencies!(nv, ["dev1.devco.net"])

            expect(nv["dev2.devco.net"][:consumes]).to eq([])
            expect(nv["dev3.devco.net"][:consumes]).to eq([])
            expect(nv["dev4.devco.net"][:consumes]).to eq([])
          end
        end

        describe "#extract_runable_nodes!" do
          it "should extract the correct nodes" do
            nv = env.node_view

            expect(nv).to include("dev1.devco.net")
            expect(env.extract_runable_nodes!(nv)).to eq([["dev1.devco.net"]])
            expect(nv).to_not include("dev1.devco.net")

            env.satisfy_dependencies!(nv, ["dev1.devco.net"])
            expect(env.extract_runable_nodes!(nv)).to eq([["dev2.devco.net", "dev3.devco.net", "dev4.devco.net"]])

            expect(nv).to be_empty
          end
        end

        describe "#node_groups" do
          it "should produce a sorted list of nodes" do
            expect(env.node_groups).to eq([["dev1.devco.net"], ["dev2.devco.net", "dev3.devco.net", "dev4.devco.net"]])
          end
        end

        describe "#application_nodes" do
          it "should extract the right nodes" do
            expect(env.application_nodes("Lamp[app1]")).to eq(["dev1.devco.net", "dev2.devco.net", "dev3.devco.net", "dev4.devco.net"])

            expect {
              env.application_nodes("Lamp[app3]")
            }.to raise_error("Unknown application Lamp[app3]")
          end
        end

        describe "#nodes" do
          it "should retrieve the right node list" do
            expect(env.nodes).to eq(["dev1.devco.net", "dev2.devco.net", "dev3.devco.net", "dev4.devco.net"])
          end
        end

        describe "#node" do
          it "should retrieve the correct node" do
            expect(env.node("dev1.devco.net")).to be(env.site_nodes["dev1.devco.net"])
          end
        end

        describe "#applications" do
          it "should fetch the valid apps" do
            expect(env.applications).to eq(["Lamp[app1]", "Lamp[app2]"])
          end
        end

        describe "#environment" do
          it "should report the site environment" do
            expect(env.environment).to eq("production")
          end
        end

        describe "#node_view" do
          it "should produce a valid node view" do
            nodes = env.node_view

            expect(nodes.keys).to eq(["dev1.devco.net", "dev2.devco.net", "dev3.devco.net", "dev4.devco.net"])

            expect(nodes["dev1.devco.net"][:produces]).to eq(["Sql[app2]", "Sql[app1]"])
            expect(nodes["dev2.devco.net"][:produces]).to eq([])
            expect(nodes["dev3.devco.net"][:produces]).to eq([])
            expect(nodes["dev4.devco.net"][:produces]).to eq([])

            expect(nodes["dev1.devco.net"][:consumes]).to eq([])
            expect(nodes["dev2.devco.net"][:consumes]).to eq(["Sql[app2]", "Sql[app1]"])
            expect(nodes["dev3.devco.net"][:consumes]).to eq(["Sql[app2]", "Sql[app1]"])
            expect(nodes["dev4.devco.net"][:consumes]).to eq(["Sql[app2]", "Sql[app1]"])

            expect(nodes["dev1.devco.net"][:resources]).to eq(["Lamp::Mysql[app2]", "Lamp::Mysql[app1]"])
            expect(nodes["dev2.devco.net"][:resources]).to eq(["Lamp::Webapp[app2-1]", "Lamp::Webapp[app1-1]"])
            expect(nodes["dev3.devco.net"][:resources]).to eq(["Lamp::Webapp[app2-2]", "Lamp::Webapp[app1-2]"])
            expect(nodes["dev4.devco.net"][:resources]).to eq(["Lamp::Webapp[app2-3]", "Lamp::Webapp[app1-3]"])

            nodes.each do |_, data|
              expect(data[:applications]).to eq(["Lamp[app2]", "Lamp[app1]"])
            end
          end
        end
      end
    end
  end
end

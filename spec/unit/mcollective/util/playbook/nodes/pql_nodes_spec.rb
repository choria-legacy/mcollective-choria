require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      class Nodes
        describe PqlNodes do
          let(:pql) { PqlNodes.new }

          describe "#discover" do
            it "should search using choria" do
              pql.from_hash("query" => "nodes {}")
              pql.choria.expects(:pql_query).with("nodes {}", true).returns(["node1"])
              expect(pql.discover).to eq(["node1"])
            end
          end

          describe "#validate_configuration!" do
            it "should not allow nil queries" do
              expect { pql.validate_configuration! }.to raise_error("No PQL query specified")
              pql.from_hash("query" => "nodes {}")
              pql.validate_configuration!
            end
          end

          describe "#from_hash" do
            it "should save the query" do
              pql.from_hash("query" => "nodes {}")
              expect(pql.instance_variable_get("@query")).to eq("nodes {}")
            end
          end
        end
      end
    end
  end
end

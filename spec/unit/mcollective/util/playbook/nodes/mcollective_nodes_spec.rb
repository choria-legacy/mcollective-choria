require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      class Nodes
        describe McollectiveNodes do
          let(:mc) { McollectiveNodes.new }

          describe "#create_and_configure_client" do
            it "should configure a client" do
              Util.stubs(:config_file_for_user).returns("/nonexisting/client.cfg")
              RPC::Client.expects(:new).with("r_agent", :configfile => "/nonexisting/client.cfg", :options => Util.default_options).returns(c = stub)

              c.expects(:progress=).with(false)
              c.expects(:discovery_method=).with("rspec_dm")

              mc.from_hash(
                "discovery_method" => "rspec_dm",
                "agents" => ["r_agent"],
                "facts" => ["country=uk"],
                "classes" => ["apache"],
                "identities" => ["dev1"],
                "compound" => "compound and filter"
              )

              c.expects(:class_filter).with("apache")
              c.expects(:fact_filter).with("country=uk")
              c.expects(:agent_filter).with("r_agent")
              c.expects(:identity_filter).with("dev1")
              c.expects(:compound_filter).with("compound and filter")

              expect(mc.create_and_configure_client).to be(c)
            end
          end

          describe "#discover" do
            it "should discover with the client" do
              mc.expects(:create_and_configure_client).returns(c = stub)
              c.expects(:discover).returns(["r1"])
              expect(mc.discover).to eq(["r1"])
            end
          end

          describe "#client" do
            it "should by default cache clients" do
              mc.expects(:create_and_configure_client).returns(c = stub)
              mc.client
              expect(mc.client).to be(c)
            end

            it "should support new clients" do
              mc.expects(:create_and_configure_client).returns(stub).twice
              mc.client(:from_cache => false)
              mc.client(:from_cache => false)
            end
          end
        end
      end
    end
  end
end

require "spec_helper"

require "mcollective/discovery/choria"

module MCollective
  describe Discovery::Choria do
    let(:discovery) { Discovery::Choria.new(Util.empty_filter, 10, 1, stub) }
    let(:choria) { discovery.choria }

    describe "#discover" do
      it "should support proxy discoveries" do
        choria.expects(:proxied_discovery?).returns(true)

        discovery.filter["cf_class"] << "puppet"

        choria.expects(:proxy_discovery_query).with("classes" => ["puppet"]).returns(["node1.example.net"])
        expect(discovery.discover).to eq(["node1.example.net"])
      end
    end

    describe "#capitalize_resource" do
      it "should correctly capitalize resources" do
        expect(discovery.capitalize_resource("foo")).to eq("Foo")
        expect(discovery.capitalize_resource("Foo")).to eq("Foo")
        expect(discovery.capitalize_resource("foo::bar")).to eq("Foo::Bar")
        expect(discovery.capitalize_resource("Foo::Bar")).to eq("Foo::Bar")
      end
    end

    describe "#numeric?" do
      it "should correctly detect numbers" do
        expect(discovery.numeric?("100")).to be_truthy
        expect(discovery.numeric?("100.2")).to be_truthy
        expect(discovery.numeric?("100.2a")).to be_falsey
      end
    end

    describe "#node_search_string" do
      it "should join queries correctly" do
        expect(
          discovery.node_search_string(["rspec1", "rspec2"])
        ).to eq("nodes[certname, deactivated] { (rspec1) and (rspec2) }")
      end
    end

    describe "#discover_nodes" do
      it "should discover nodes correctly" do
        expect(
          discovery.discover_nodes(["/x/", "y", 'pql: nodes[certname] { facts_environment = "production" }'])
        ).to eq('certname ~ "[xX]" or certname = "y" or certname in nodes[certname] { facts_environment = "production" }')
      end
    end

    describe "#discover_classes" do
      it "should correctly discover classes" do
        expect(
          discovery.discover_classes(["/foo/", "bar"])
        ).to eq('resources {type = "Class" and title ~ "[fF][oO][oO]"} and resources {type = "Class" and title = "Bar"}')
      end
    end

    describe "#discover_facts" do
      it "should support =~" do
        expect(
          discovery.discover_facts([:fact => "f", :operator => "=~", :value => "v"])
        ).to eq('inventory {facts.f ~ "[vV]"}')
      end

      it "should support ==" do
        expect(
          discovery.discover_facts([:fact => "f", :operator => "==", :value => "v"])
        ).to eq('inventory {facts.f = "v"}')
      end

      it "should support !=" do
        expect(
          discovery.discover_facts([:fact => "f", :operator => "!=", :value => "v"])
        ).to eq('inventory {!(facts.f = "v")}')
      end

      it "should fail for other operators when comparing strings" do
        expect do
          discovery.discover_facts([:fact => "f", :operator => ">=", :value => "v"])
        end.to raise_error("Do not know how to do string fact comparisons using the '>=' operator with PuppetDB")
      end

      it "should support other operators" do
        expect(
          discovery.discover_facts([:fact => "f", :operator => ">=", :value => 1])
        ).to eq("inventory {facts.f >= 1}")
      end
    end

    describe "#string_regexi" do
      it "should correctly make a case insensitive regex" do
        expect(discovery.string_regexi("a1_$-2bZ")).to eq("[aA]1_$-2[bB][zZ]")
      end
    end

    describe "#discover_classes" do
      it "should support plain strings and regex" do
        expect(
          discovery.discover_classes(["/regex_class/", "specific_class"])
        ).to eq('resources {type = "Class" and title ~ "[rR][eE][gG][eE][xX]_[cC][lL][aA][sS][sS]"} and resources {type = "Class" and title = "Specific_class"}')
      end
    end

    describe "#discover_agents" do
      it "should search for correct classes" do
        # rubocop:disable Metrics/LineLength
        expect(
          discovery.discover_agents(["rpcutil", "rspec1", "/rs/"])
        ).to eq('(resources {type = "Class" and title = "Mcollective::Service"} or resources {type = "Class" and title = "Choria::Service"}) and resources {type = "File" and tag = "mcollective_agent_rspec1_server"} and resources {type = "File" and tag ~ "mcollective_agent_.*?[rR][sS].*?_server"}')
        # rubocop:enable Metrics/LineLength
      end
    end

    describe "#discover_collective" do
      it "should search in facts" do
        expect(discovery.discover_collective("rspec_collective")).to eq(
          'certname in inventory[certname] { facts.mcollective.server.collectives.match("\d+") = "rspec_collective" }'
        )
      end
    end
  end
end

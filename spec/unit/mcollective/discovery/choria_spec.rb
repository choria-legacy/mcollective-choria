require "spec_helper"

require "mcollective/discovery/choria"

module MCollective
  describe Discovery::Choria do
    let(:discovery) { Discovery::Choria.new({}, 10, 1, stub) }

    describe "#capitalize_resource" do
      it "should correctly capitalize resources" do
        expect(discovery.capitalize_resource("foo")).to eq("Foo")
        expect(discovery.capitalize_resource("Foo")).to eq("Foo")
        expect(discovery.capitalize_resource("foo::bar")).to eq("Foo::Bar")
        expect(discovery.capitalize_resource("Foo::Bar")).to eq("Foo::Bar")
      end
    end

    describe "#query" do
      it "should query and parse" do
        discovery.choria.expects(:check_ssl_setup)
        discovery.expects(:http_get).with("/pdb/query/v4?query=nodes+%7B+%7D").returns(get = stub)
        discovery.https.expects(:request).with(get).returns([stub(:code => "200"), '{"rspec":1}'])
        expect(discovery.query("nodes { }")).to eq("rspec" => 1)
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

    describe "#extract_certs" do
      it "should extract all certname fields" do
        expect(
          discovery.extract_certs([{"certname" => "one"}, {"certname" => "two"}, {"x" => "rspec"}])
        ).to eq(["one", "two"])
      end
    end

    describe "#discover_nodes" do
      it "should discover nodes correctly" do
        expect(
          discovery.discover_nodes(["/x/", "y"])
        ).to eq('certname ~ "[xX]" or certname = "y"')
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
        ).to eq('facts {name = "f" and value ~ "[vV]"}')
      end

      it "should support ==" do
        expect(
          discovery.discover_facts([:fact => "f", :operator => "==", :value => "v"])
        ).to eq('facts {name = "f" and value = "v"}')
      end

      it "should support !=" do
        expect(
          discovery.discover_facts([:fact => "f", :operator => "!=", :value => "v"])
        ).to eq('facts {name = "f" and !(value = "v")}')
      end

      it "should support other operators" do
        expect(
          discovery.discover_facts([:fact => "f", :operator => ">=", :value => "v"])
        ).to eq('facts {name = "f" and value >= "v"}')

        expect(
          discovery.discover_facts([:fact => "f", :operator => ">=", :value => 1])
        ).to eq('facts {name = "f" and value >= 1}')
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
        ).to eq('resources {type = "Class" and title = "Mcollective::Service"} and resources {type = "File" and tag = "mcollective_agent_rspec1_server"} and resources {type = "File" and tag ~ "mcollective_agent_.*?[rR][sS].*?_server"}')
        # rubocop:enable Metrics/LineLength
      end
    end

    describe "#discover_collective" do
      it "should search in facts" do
        expect(discovery.discover_collective("rspec_collective")).to eq(
          'certname in fact_contents[certname] {path ~> ["mcollective", "server", "collectives", "\\\\d"] and value = "rspec_collective"}'
        )
      end
    end
  end
end

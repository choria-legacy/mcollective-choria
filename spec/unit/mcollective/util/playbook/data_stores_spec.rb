require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      describe DataStores do
        let(:ds) { DataStores.new(stub) }
        let(:stores) { ds.instance_variable_get("@stores") }
        let(:store) { ds["mem_store"] }
        let(:playbook_fixture) { YAML.load(File.read("spec/fixtures/playbooks/playbook.yaml")) }

        before(:each) do
          ds.from_hash(playbook_fixture["data_stores"])
        end

        describe "#lock_timeout" do
          it "should get the right timeout" do
            expect(ds.lock_timeout("mem_store")).to eq(20)
            expect(ds.lock_timeout("another")).to eq(120)
            expect { ds.lock_timeout("rspec") }.to raise_error("Unknown data store rspec")
          end
        end

        describe "#lock_ttl" do
          it "should get the right ttl" do
            expect(ds.lock_ttl("mem_store")).to eq(10)
            expect(ds.lock_ttl("another")).to eq(60)
            expect { ds.lock_ttl("rspec") }.to raise_error("Unknown data store rspec")
          end
        end

        describe "#from_hash" do
          it "should create the right data" do
            ds.from_hash(playbook_fixture["data_stores"])
            expect(stores.keys).to eq(["mem_store", "another"])
            expect(stores["mem_store"]).to include(
              :properties => {"type" => "memory", "timeout" => 20, "ttl" => 10},
              :type => "memory",
              :lock_timeout => 20,
              :lock_ttl => 10,
              :store => a_kind_of(DataStores::MemoryDataStore)
            )
          end
        end

        describe "#store_for" do
          it "should create the correct type of store" do
            expect(ds.store_for("memory")).to be_a(DataStores::MemoryDataStore)

            expect { ds.store_for("rspec") }.to raise_error("Cannot find a handler for Data Store type rspec")
          end
        end

        describe "#include?" do
          it "should correctly check for known stores" do
            expect(ds.include?("mem_store")).to be(true)
            expect(ds.include?("rspec")).to be(false)
          end
        end

        describe "#keys" do
          it "should list all stores" do
            expect(ds.keys).to eq(["mem_store", "another"])
          end
        end

        describe "#[]" do
          it "should fetch the right store" do
            expect(ds["mem_store"]).to be(stores["mem_store"][:store])
          end
        end

        describe "#release" do
          it "should release the right lock" do
            store.expects(:release).with("rspec")
            ds.release("mem_store/rspec")
          end
        end

        describe "#lock" do
          it "should lock the right lock" do
            store.expects(:lock).with("rspec", 20, 10)
            ds.lock("mem_store/rspec")
          end
        end

        describe "#members" do
          it "should fetch the right service members" do
            store.expects(:members).with("rspec").returns(["node1"])
            expect(ds.members("mem_store/rspec")).to eq(["node1"])
          end
        end

        describe "#delete" do
          it "should delete the right key" do
            store.expects(:delete).with("rspec")
            ds.delete("mem_store/rspec")
          end
        end

        describe "#write" do
          it "should write the right values" do
            store.expects(:write).with("rspec", "rsv").returns("rsv")
            expect(ds.write("mem_store/rspec", "rsv")).to eq("rsv")
          end
        end

        describe "#read" do
          it "should read the right key from the store" do
            store.expects(:read).with("rspec").returns("rsv")
            expect(ds.read("mem_store/rspec")).to eq("rsv")
          end
        end

        describe "#parse_path" do
          it "should correctly parse the path" do
            expect(ds.parse_path("mem_store/y")).to eq(["mem_store", "y"])
            expect {ds.parse_path("x") }.to raise_error("Invalid data store path x")
          end
        end

        describe "#valid_path?" do
          it "should correctly validate paths" do
            expect(ds.valid_path?("x/y")).to be(false)
            expect(ds.valid_path?("mem_store/y")).to be(true)
          end
        end
      end
    end
  end
end

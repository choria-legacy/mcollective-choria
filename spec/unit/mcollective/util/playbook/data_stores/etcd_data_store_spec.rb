require "spec_helper"
require "mcollective/util/playbook"
require "diplomat"

module MCollective
  module Util
    class Playbook
      class DataStores
        describe EtcdDataStore do
          let(:ds) { EtcdDataStore.new("rspec", stub) }

          before(:each) do
            ds.from_hash(
              "url" => "http://etcd.example.net:2379",
              "user" => "rspec_user",
              "password" => "rspec_pass"
            )
          end

          describe "#conn" do
            it "should default to localhost" do
              ds.from_hash({})
              Etcdv3.expects(:new).with(:url => "http://127.0.0.1:2379")
              ds.conn
            end

            it "should support url, user and pass" do
              Etcdv3.expects(:new).with(
                :url => "http://etcd.example.net:2379",
                :user => "rspec_user",
                :password => "rspec_pass"
              )

              ds.conn
            end
          end

          describe "#delete" do
            it "should delete the data" do
              ds.stubs(:conn).returns(stub)
              ds.conn.expects(:del).with("x")
              ds.delete("x")
            end
          end

          describe "#write" do
            it "should store the data" do
              ds.stubs(:conn).returns(stub)
              ds.conn.expects(:put).with("x", "value")
              ds.write("x", "value")
            end
          end

          describe "#read" do
            it "should read the data" do
              ds.stubs(:conn).returns(stub)
              result = stub(:kvs => [stub(:value => "value")])
              ds.conn.expects(:get).with("x").returns(result)
              expect(ds.read("x")).to eq("value")
            end

            it "should fail gracefully when no data is found" do
              ds.stubs(:conn).returns(stub)
              result = stub(:kvs => [])
              ds.conn.expects(:get).with("x").returns(result)

              expect { ds.read("x") }.to raise_error("Could not find key x")
            end
          end
        end
      end
    end
  end
end

require "spec_helper"
require "mcollective/util/bolt_support"
require "puppet"
require "diplomat"

module MCollective
  module Util
    describe BoltSupport do
      let(:playbook) { Playbook.new("error") }
      let(:support) { BoltSupport.new }

      before(:each) do
        Log.stubs(:error)
        support.stubs(:playbook).returns(playbook)
      end

      describe "#data_lock" do
        it "should lock and release" do
          playbook.data_stores.stubs(:prepare)
          playbook.data_stores.expects(:lock).with("plan_store/rspec").twice
          playbook.data_stores.expects(:release).with("plan_store/rspec").twice

          expect do
            support.data_lock("rspec", "type" => "consul") { raise("rspec failure") }
          end.to raise_error("rspec failure")

          expect(support.data_lock("rspec", "type" => "consul") { "rspec result" }).to eq("rspec result")
        end
      end

      describe "#run_task" do
        it "should invoke the tasks and return an execution_result" do
          result = support.run_task("shell", "command" => "/bin/echo 'hello world'")

          expect(result).to eq(
            "localhost" => {
              "value" => "hello world"
            }
          )
        end

        it "should support fail_ok" do
          expect { support.run_task("shell", "command" => "/bin/false") }.to raise_error(
            "Command failed with code 1"
          )

          result = support.run_task("shell", "command" => "/bin/false", "fail_ok" => true)

          expect(result).to eq(
            "localhost" => {
              "value" => "",
              "error" => {
                "msg" => "Command failed with code 1"
              }
            }
          )
        end
      end

      describe ".loglevel" do
        it "should convert correctly" do
          [
            [:notice, "warn"],
            [:warning, "warn"],
            [:err, "error"],
            [:alert, "fatal"],
            [:emerg, "fatal"],
            [:crit, "fatal"]
          ].each do |p, m|
            Puppet::Util::Log.stubs(:level).returns(p)
            expect(BoltSupport.loglevel).to eq(m)
          end
        end
      end

      describe "#data_write" do
        it "should write the right data" do
          tf = Tempfile.new("rspec")
          r = support.data_write("hello", "world",
                                 "type" => "file",
                                 "format" => "yaml",
                                 "file" => tf.path)

          expect(r).to eq("world")
          expect(YAML.safe_load(File.read(tf.path))).to eq("hello" => "world")
          tf.unlink
        end
      end

      describe "#data_read" do
        it "should read the right data" do
          r = support.data_read("hello",
                                "type" => "file",
                                "format" => "yaml",
                                "file" => File.expand_path("spec/fixtures/playbooks/file_data.yaml"))

          expect(r).to eq("world")
        end
      end

      describe "#discover_nodes" do
        it "should support requests without uses" do
          playbook.stubs(:uses).returns(u = stub)
          u.expects(:from_hash).with({})

          result = support.discover_nodes("yaml",
                                          "source" => File.expand_path("spec/fixtures/playbooks/nodes.yaml"),
                                          "group" => "uk")

          expect(result).to eq(["node1.example.net", "node2.example.net", "node3.example.net"])
        end

        it "should support requests with uses" do
          playbook.stubs(:uses).returns(u = stub)
          u.expects(:from_hash).with("rpcutil" => "1.2.3")
          support.stubs(:nodes).returns(n = stub)
          n.expects(:from_hash).with(
            "task_nodes" => {
              "source" => File.expand_path("spec/fixtures/playbooks/nodes.yaml"),
              "group" => "uk",
              "type" => "yaml",
              "uses" => ["rpcutil"]
            }
          )
          n.expects(:prepare)
          n.expects(:[]).with("task_nodes").returns(["n1"])

          result = support.discover_nodes("yaml",
                                          "source" => File.expand_path("spec/fixtures/playbooks/nodes.yaml"),
                                          "group" => "uk",
                                          "uses" => {"rpcutil" => "1.2.3"})

          expect(result).to eq(["n1"])
        end
      end
    end
  end
end

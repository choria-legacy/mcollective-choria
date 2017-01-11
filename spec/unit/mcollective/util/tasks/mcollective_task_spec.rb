require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      class Tasks
        describe McollectiveTask do
          let(:task) { McollectiveTask.new }

          describe "#run" do
            before(:each) do
              task.from_hash(
                "nodes" => ["node1", "node2"],
                "action" => "puppet.disable",
                "batch_size" => 10,
                "description" => "disable puppet",
                "post" => ["summarize"],
                "silent" => false,
                "properties" => {
                  :message => "rspec"
                }
              )
            end

            it "should run correctly" do
              result_data = {
                :agent => "puppet",
                :action => "disable",
                :sender => "example.net",
                :statuscode => 0,
                :statusmsg => "OK",
                :data => {
                  :status => "Succesfully locked the Puppet agent: Disabled via MCollective by choria=rip.mcollective at 2016-12-25 07:59",
                  :enabled => false
                }
              }

              rpc_result1 = RPC::Result.new("puppet", "disable", result_data)
              rpc_result2 = RPC::Result.new("puppet", "disable", result_data)

              task.stubs(:client).returns(mc_client = stub)
              mc_client.stubs(:stats).returns(mc_stats = stub(:requestid => "123"))
              mc_client.expects(:disable).with(:message => "rspec").multiple_yields([[:x, rpc_result1]], [[:x, rpc_result2]])

              task.expects(:log_reply).with(rpc_result1)
              task.expects(:log_reply).with(rpc_result2)
              task.expects(:log_summarize).with(mc_stats)
              task.expects(:log_results).with(mc_stats, [rpc_result1, rpc_result2])
              task.expects(:run_result).with(mc_stats, [rpc_result1, rpc_result2])
              task.run
            end

            it "should fail gracefully" do
              task.expects(:client).raises("rspec failure")
              expect(task.run).to eq([false, "Could not create request for puppet#disable: RuntimeError: rspec failure", []])
            end
          end

          describe "#request_success?" do
            it "should correctly determine succesful requests" do
              expect(task.request_success?(stub(:failcount => 0, :okcount => 1, :noresponsefrom => []))).to be(true)
              expect(task.request_success?(stub(:failcount => 1, :okcount => 1, :noresponsefrom => []))).to be(false)
              expect(task.request_success?(stub(:failcount => 0, :okcount => 0, :noresponsefrom => []))).to be(false)
              expect(task.request_success?(stub(:failcount => 0, :okcount => 0, :noresponsefrom => ["node1"]))).to be(false)
            end
          end

          describe "#run_result" do
            let(:result_data) do
              {
                :agent => "puppet",
                :action => "disable",
                :sender => "example.net",
                :statuscode => 0,
                :statusmsg => "OK",
                :data => {
                  :status => "Succesfully locked the Puppet agent: Disabled via MCollective by choria=rip.mcollective at 2016-12-25 07:59",
                  :enabled => false
                }
              }
            end
            let(:rpc_result) { RPC::Result.new("puppet", "disable", result_data) }

            before(:each) do
              task.instance_variable_set("@agent", "puppet")
              task.instance_variable_set("@action", "disable")
            end

            it "should create a correct fail result set" do
              stats = stub(:requestid => "123", :failcount => 1, :noresponsefrom => [], :okcount => 0)

              expect(task.run_result(stats, [rpc_result])).to eq(
                [
                  false,
                  "Failed request 123 for puppet#disable on 1 failed node(s)",
                  [
                    {
                      "agent" => "puppet",
                      "action" => "disable",
                      "sender" => "example.net",
                      "statuscode" => 0,
                      "statusmsg" => "OK",
                      "data" => result_data[:data],
                      "requestid" => "123"
                    }
                  ]
                ]
              )
            end

            it "should create a correct success result set" do
              stats = stub(:requestid => "123", :failcount => 0, :noresponsefrom => [], :okcount => 1)

              expect(task.run_result(stats, [rpc_result])).to eq(
                [
                  true,
                  "Successful request 123 for puppet#disable on 1 node(s)",
                  [
                    {
                      "agent" => "puppet",
                      "action" => "disable",
                      "sender" => "example.net",
                      "statuscode" => 0,
                      "statusmsg" => "OK",
                      "data" => result_data[:data],
                      "requestid" => "123"
                    }
                  ]
                ]
              )
            end
          end

          describe "#from_hash" do
            it "should initialize correctly" do
              task.from_hash(
                "nodes" => ["node1", "node2"],
                "action" => "puppet.disable",
                "batch_size" => 10,
                "description" => "disable puppet",
                "post" => ["summarize"],
                "silent" => false,
                "properties" => {
                  :message => "rspec"
                }
              )

              expect(task.instance_variable_get("@nodes")).to eq(["node1", "node2"])
              expect(task.instance_variable_get("@agent")).to eq("puppet")
              expect(task.instance_variable_get("@action")).to eq("disable")
              expect(task.instance_variable_get("@batch_size")).to eq(10)
              expect(task.instance_variable_get("@post")).to eq(["summarize"])
              expect(task.instance_variable_get("@log_replies")).to eq(true)
              expect(task.instance_variable_get("@properties")).to eq(:message => "rspec")
            end
          end

          describe "#parse_action" do
            it "should parse agent and action" do
              expect(task.parse_action("puppet.enable")).to eq(["puppet", "enable"])
            end
          end

          describe "#validate_configuration!" do
            it "should not support unbounded node lists" do
              expect { task.validate_configuration! }.to raise_error("Nodes need to be supplied, refusing to run against empty node list")

              task.instance_variable_get("@nodes") << "node1"
              task.validate_configuration!
            end
          end

          describe "#create_and_configure_client" do
            before(:each) do
              Util.stubs(:config_file_for_user).returns("/nonexisting/client.cfg")
            end

            it "should create a client" do
              RPC::Client.expects(:new).with("rspec", :configfile => "/nonexisting/client.cfg").returns(client = stub)
              task.instance_variable_set("@agent", "rspec")
              task.instance_variable_set("@batch_size", 10)
              task.instance_variable_set("@nodes", ["node1", "node2"])
              client.expects(:progress=).with(false)
              client.expects(:batch_size=).with(10)
              client.expects(:discover).with(:nodes => ["node1", "node2"])
              expect(task.create_and_configure_client).to be(client)
            end
          end

          describe "#client" do
            it "should make a client and cache it by default" do
              task.expects(:create_and_configure_client).returns(c = stub)
              expect(task.client).to be(c)
              expect(task.client).to be(c)
            end

            it "should support always making a client" do
              task.expects(:create_and_configure_client).returns(c1 = stub, c2 = stub).twice
              expect(task.client(false)).to be(c1)
              expect(task.client(false)).to be(c2)
            end
          end
        end
      end
    end
  end
end

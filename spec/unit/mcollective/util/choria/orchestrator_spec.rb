require "spec_helper"
require "mcollective/util/choria"

module MCollective
  module Util
    class Choria
      describe Orchestrator do
        let(:choria) { stub(:certname => "rspec.cert", :puppet_environment => stub) }
        let(:puppet) { stub }
        let(:orc) { Orchestrator.new(choria, puppet, 10) }
        let(:last_applying) do
          results_maker(3) do |c, result|
            result[:applying] = (c == 3)
          end
        end

        let(:all_applying) do
          results_maker(3) do |_, result|
            result[:applying] = true
          end
        end

        let(:none_applying) do
          results_maker(3) do |_, result|
            result[:applying] = false
          end
        end

        def results_maker(count)
          (0..count).map do |i|
            result = {
              :sender => "sender#{i}",
              :data => {}
            }
            yield(i, result[:data])
            stub(:results => result)
          end
        end

        before(:each) do
          orc.stubs(:time).returns(Time.now)
          orc.stubs(:puts)
          orc.environment.stubs(:nodes).returns(["1", "2", "3"])
        end

        describe "#check_result" do
          it "should detect good results" do
            expect(orc.check_result(:body => {:statuscode => 0})).to be_truthy
          end

          it "should detect bad results" do
            expect(orc.check_result({:senderid => "rspec.node", :senderagent => "rspec_agent", :body => {:statuscode => 1}}, false)).to be_falsey
            expect {
              orc.check_result(:senderid => "rspec.node", :senderagent => "rspec_agent", :body => {:statuscode => 1, :statusmsg => "fail message"})
            }.to raise_error(UserError, "Failed response from node rspec.node agent rspec_agent: fail message")
          end
        end

        describe "#run_plan" do
          it "should fail when all nodes arent enabled" do
            orc.expects(:all_nodes_enabled?).with(["1", "2", "3"]).returns(false)
            orc.expects(:disable_nodes).with(["1", "2", "3"])
            expect {
              orc.run_plan
            }.to raise_error(UserError, "Not all nodes in the plan are enabled, cannot continue")
          end

          it "should run nodes by group" do
            seq = sequence(:run)
            nodes = ["1", "2", "3"]

            orc.environment.stubs(:each_node_group).multiple_yields([["1"]], [["2", "3"]])

            orc.expects(:all_nodes_enabled?).with(nodes).returns(true)
            orc.expects(:disable_nodes).with(["1", "2", "3"]).in_sequence(seq)
            orc.expects(:wait_till_nodes_idle).with(["1", "2", "3"]).in_sequence(seq)
            orc.expects(:run_nodes).with(["1"]).in_sequence(seq)
            orc.expects(:failed_nodes).with(["1"]).returns([]).in_sequence(seq)
            orc.expects(:run_nodes).with(["2", "3"]).in_sequence(seq)
            orc.expects(:failed_nodes).with(["2", "3"]).returns([]).in_sequence(seq)
            orc.expects(:enable_nodes).with(["1", "2", "3"]).in_sequence(seq)

            orc.run_plan
          end

          it "should support batches" do
            seq = sequence(:run)
            nodes = ["1", "2", "3"]

            orc.batch_size = 1

            orc.environment.stubs(:each_node_group).multiple_yields([["1"]], [["2", "3"]])

            orc.expects(:all_nodes_enabled?).with(nodes).returns(true)
            orc.expects(:disable_nodes).with(["1", "2", "3"]).in_sequence(seq)
            orc.expects(:wait_till_nodes_idle).with(["1", "2", "3"]).in_sequence(seq)
            orc.expects(:run_nodes).with(["1"]).in_sequence(seq)
            orc.expects(:failed_nodes).with(["1"]).returns([]).in_sequence(seq)
            orc.expects(:run_nodes).with(["2"]).in_sequence(seq)
            orc.expects(:failed_nodes).with(["2"]).returns([]).in_sequence(seq)
            orc.expects(:run_nodes).with(["3"]).in_sequence(seq)
            orc.expects(:failed_nodes).with(["3"]).returns([]).in_sequence(seq)
            orc.expects(:enable_nodes).with(["1", "2", "3"]).in_sequence(seq)

            orc.run_plan
          end

          it "should fail on any failues" do
            nodes = ["1", "2", "3"]
            orc.batch_size = 1

            orc.environment.stubs(:each_node_group).multiple_yields([["1"]], [["2", "3"]])

            orc.expects(:all_nodes_enabled?).with(nodes).returns(true)
            orc.expects(:disable_nodes).with(["1", "2", "3"])
            orc.expects(:wait_till_nodes_idle).with(["1", "2", "3"])
            orc.expects(:run_nodes).with(["1"])
            orc.expects(:failed_nodes).with(["1"]).returns([])
            orc.expects(:run_nodes).with(["2"])
            orc.expects(:failed_nodes).with(["2"]).returns(["2"])
            orc.expects(:run_nodes).with(["3"]).never
            orc.expects(:failed_nodes).with(["3"]).never
            orc.expects(:enable_nodes).with(["1", "2", "3"])

            expect {
              orc.run_plan
            }.to raise_error(Abort)
          end
        end

        describe "#run_nodes" do
          it "should do the run correctly" do
            nodes = ["1", "2", "3"]

            seq = sequence(:run)

            orc.expects(:enable_nodes).with(nodes).in_sequence(seq)
            orc.expects(:rpc_and_check).with(:runonce, nodes, :splay => false, :use_cached_catalog => false, :force => true).in_sequence(seq)
            orc.expects(:wait_till_nodes_start).with(nodes).in_sequence(seq)
            orc.expects(:wait_till_nodes_idle).with(nodes).in_sequence(seq)
            orc.expects(:disable_nodes).with(nodes).in_sequence(seq)

            orc.run_nodes(nodes)
          end
        end

        describe "#all_nodes_enabled?" do
          it "should correctly detect disabled nodes" do
            r = results_maker(3) do |c, result|
              result[:enabled] = (c == 3)
            end

            orc.expects(:rpc_and_check).with(:status, ["1", "2", "3"]).returns(r)

            expect(orc.all_nodes_enabled?(["1", "2", "3"])).to be_falsey

            r = results_maker(3) do |_, result|
              result[:enabled] = true
            end

            orc.expects(:rpc_and_check).with(:status, ["1", "2", "3"]).returns(r)

            expect(orc.all_nodes_enabled?(["1", "2", "3"])).to be_truthy
          end
        end

        describe "#failed_nodes" do
          it "should find failed nodes" do
            r = results_maker(3) do |c, result|
              result[:failed_resources] = (c == 3 ? 1 : 0)
            end

            orc.stubs(:rpc_and_check).with(:last_run_summary, ["1", "2", "3"]).returns(r)
            expect(orc.failed_nodes(["1", "2", "3"])).to eq(["sender3"])
          end

          it "should handle all green nodes" do
            r = results_maker(3) do |_, result|
              result[:failed_resources] = 0
            end

            orc.stubs(:rpc_and_check).with(:last_run_summary, ["1", "2", "3"]).returns(r)
            expect(orc.failed_nodes(["1", "2", "3"])).to eq([])
          end
        end

        describe "#wait_till_nodes_idle" do
          it "should try up to specified times and pass on success" do
            orc.expects(:sleep).with(1).times(2)
            orc.expects(:rpc_and_check).with(:status, ["1", "2", "3"]).returns(all_applying)
               .then.returns(last_applying)
               .then.returns(none_applying)
               .times(3)

            orc.wait_till_nodes_idle(["1", "2", "3"], 3, 1)
          end

          it "should timeout correctly" do
            orc.expects(:sleep).with(1).times(3)
            orc.expects(:rpc_and_check).with(:status, ["1", "2", "3"]).returns(all_applying)
               .then.returns(last_applying)
               .then.returns(last_applying)
               .times(3)

            expect {
              orc.wait_till_nodes_idle(["1", "2", "3"], 3, 1)
            }.to raise_error(Abort)
          end
        end

        describe "#wait_till_nodes_start" do
          it "should try up to specified times and pass on success" do
            orc.expects(:sleep).with(1).times(2)
            orc.expects(:rpc_and_check).with(:status, ["1", "2", "3"]).returns(last_applying)
               .then.returns(last_applying)
               .then.returns(all_applying)
               .times(3)

            orc.wait_till_nodes_start(["1", "2", "3"], 3, 1)
          end

          it "should timeout correctly" do
            orc.expects(:sleep).with(1).times(3)
            orc.expects(:rpc_and_check).with(:status, ["1", "2", "3"]).returns(last_applying)
               .then.returns(last_applying)
               .then.returns(last_applying)
               .times(3)

            expect {
              orc.wait_till_nodes_start(["1", "2", "3"], 3, 1)
            }.to raise_error(Abort)
          end
        end

        describe "#enable_nodes" do
          it "should enable the provided nodes" do
            orc.expects(:rpc_and_check).with(:enable, ["1", "2"])
            orc.enable_nodes(["1", "2"])
          end
        end

        describe "#disable_nodes" do
          it "should disable the provided nodes" do
            orc.expects(:rpc_and_check).with(:disable, ["1", "2"], :message => "Disabled during orchastration job initiated by rspec.cert at %s" % orc.time)
            orc.disable_nodes(["1", "2"])
          end
        end
      end
    end
  end
end

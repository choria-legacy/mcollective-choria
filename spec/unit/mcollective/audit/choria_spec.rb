require "spec_helper"
require "mcollective/audit/choria"

module MCollective
  module Audit
    describe Choria do
      let(:choria) { Choria.new }

      describe(:audit_request) do
        it "should warn about rpcaudit.logfile" do
          Config.instance.stubs(:pluginconf).returns({})
          Log.expects(:warn).with("Auditing is not functional because rpcaudit.logfile is not set")
          File.expects(:writable?).never

          choria.audit_request(stub, stub)
        end

        it "should log the correct data" do
          msg = {
            :msgtime => 1483774088,
            :senderid => "rspec.example.net",
            :requestid => "rspec.req.id",
            :callerid => "choria=rspec",
            :body => {
              :agent => "rspec_agent",
              :action => "rspec_action",
              :data => {:rspec => :data}
            }
          }

          Config.instance.stubs(:pluginconf).returns("rpcaudit.logfile" => "/nonexisting/audit.log")
          File.expects(:open).with("/nonexisting/audit.log", "a").yields(file = StringIO.new)
          Time.expects(:now).returns(Time.at(1483774088))

          choria.audit_request(RPC::Request.new(msg, stub), stub)

          expected = {
            "timestamp" => "2017-01-07T07:28:08.000000+0000",
            "request_id" => "rspec.req.id",
            "request_time" => 1483774088,
            "caller" => "choria=rspec",
            "sender" => "rspec.example.net",
            "agent" => "rspec_agent",
            "action" => "rspec_action",
            "data" => {
              :rspec => :data
            }
          }.to_json

          expect(file.string.chomp).to eq(expected)
        end
      end
    end
  end
end

require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      class Tasks
        describe WebhookTask do
          let(:task) { WebhookTask.new(stub) }

          before(:each) do
            uuid = MCollective::SSL.uuid("rspec")
            MCollective::SSL.stubs(:uuid).returns(uuid)

            task.from_hash(
              "headers" => {"X-Header" => "x_value"},
              "data" => {"rspec1" => 1, "rspec2" => 2},
              "uri" => "http://localhost/rspec?foo=bar",
              "method" => "POST"
            )
          end

          describe "#run" do
            it "should handle 200 as success" do
              task.expects(:choria).returns(choria = stub)
              choria.expects(:https).with(:target => "localhost", :port => 80).returns(http = stub)
              http.expects(:use_ssl=).with(false)
              http.expects(:request).returns(stub(:code => "200", :body => "ok"))
              expect(task.run).to eq(
                [
                  true,
                  "Successfully sent POST request to webhook http://localhost/rspec?foo=bar with id 479d1982-120a-5ba8-8664-1f16a6504371",
                  ["ok"]
                ]
              )
            end

            it "should handle !200 as failure" do
              task.expects(:choria).returns(choria = stub)
              choria.expects(:https).with(:target => "localhost", :port => 80).returns(http = stub)
              http.expects(:use_ssl=).with(false)
              http.expects(:request).returns(stub(:code => "404", :body => "not found"))
              expect(task.run).to eq(
                [
                  false,
                  "Failed to send POST request to webhook http://localhost/rspec?foo=bar with id 479d1982-120a-5ba8-8664-1f16a6504371: 404: not found",
                  ["not found"]
                ]
              )
            end
          end

          describe "#http_request" do
            it "should invoke the right method" do
              task.instance_variable_set("@method", "GET")
              task.expects(:http_get_request).with(:rspec).returns(:rspec)
              expect(task.http_request(:rspec)).to eq(:rspec)

              task.instance_variable_set("@method", "POST")
              task.expects(:http_post_request).with(:rspec).returns(:rspec)
              expect(task.http_request(:rspec)).to eq(:rspec)

              task.instance_variable_set("@method", "RSPEC")
              task.expects(:http_get_request).never
              task.expects(:http_post_request).never
              expect { task.http_request(:rspec) }.to raise_error("Unknown request method RSPEC")
            end
          end

          describe "#http_post_request" do
            it "should create the right request" do
              uri = task.create_uri
              post = stub(:https)
              uuid = MCollective::SSL.uuid("rspec")
              MCollective::SSL.stubs(:uuid).returns(uuid)

              Net::HTTP::Post.expects(:new).with(
                uri.request_uri,
                "User-Agent" => "Choria Playbooks http://choria.io",
                "X-Header" => "x_value",
                "Content-Type" => "application/json",
                "X-Choria-Request-ID" => "479d1982-120a-5ba8-8664-1f16a6504371"
              ).returns(post)
              post.expects(:body=).with({"rspec1" => 1, "rspec2" => 2}.to_json)

              expect(task.http_post_request(uri)).to be(post)
            end
          end

          describe "#http_get_request" do
            it "should create the right request" do
              uri = task.create_uri
              get = stub(:https)

              Net::HTTP::Get.expects(:new).with(
                uri.request_uri,
                "User-Agent" => "Choria Playbooks http://choria.io",
                "X-Header" => "x_value",
                "X-Choria-Request-ID" => "479d1982-120a-5ba8-8664-1f16a6504371"
              ).returns(get)

              expect(task.http_get_request(uri)).to be(get)
            end
          end

          describe "#create_uri" do
            it "should support GET method" do
              task.instance_variable_set("@method", "GET")
              expect(task.create_uri.to_s).to eq("http://localhost/rspec?foo=bar&rspec1=1&rspec2=2")
            end

            it "should support other methods" do
              expect(task.create_uri.to_s).to eq("http://localhost/rspec?foo=bar")
            end
          end
        end
      end
    end
  end
end

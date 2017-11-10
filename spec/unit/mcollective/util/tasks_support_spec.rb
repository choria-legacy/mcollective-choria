require "spec_helper"
require "mcollective/util/choria"
require "mcollective/util/tasks_support"

module MCollective
  module Util
    describe TasksSupport do
      let(:cache) { "/tmp/tasks-cache-#{$$}" }
      let(:choria) { Choria.new(false) }
      let(:ts) { TasksSupport.new(choria, cache) }
      let(:fixture) { JSON.parse(File.read("spec/fixtures/tasks/choria_ls_metadata.json")) }
      let(:fixture_rb) { File.read("spec/fixtures/tasks/choria_ls.rb") }
      let(:file) { fixture["files"].first }

      before(:each) do
        choria.stubs(:check_ssl_setup).returns(true)
      end

      after(:all) do
        FileUtils.rm_rf("/tmp/tasks-cache-#{$$}")
      end

      describe "#download_task" do
        it "should download every file" do
          files = fixture["files"]
          files << files[0]
          files[1]["filename"] = "file2.rb"

          ts.expects(:task_file?).with(files[0]).returns(true).once
          ts.expects(:task_file?).with(files[1]).returns(true).once

          ts.expects(:cache_task_file).never

          expect(ts.download_task(fixture)).to be(true)
        end

        it "should support retries" do
          ts.expects(:cache_task_file).with(file).raises("test failure").then.returns(true).twice
          ts.expects(:task_file?).with(file).returns(false)
          expect(ts.download_task(fixture)).to be(true)
        end

        it "should attempt twice and fail after" do
          ts.expects(:cache_task_file).with(file).raises("test failure").twice
          ts.stubs(:task_file?).returns(false)
          expect(ts.download_task(fixture)).to be(false)
        end
      end

      describe "#cache_task_file" do
        before(:each) do
          choria.expects(:puppet_server).returns(:target => "stubpuppet", :port => 8140)
          FileUtils.rm_rf(cache)
        end

        it "should download and cache the file" do
          expect(ts.task_file?(file)).to be(false)

          stub_request(:get, "https://stubpuppet:8140/puppet/v3/file_content/tasks/choria/ls.rb?environment=production")
            .with(:headers => {"Accept" => "application/octet-stream"})
            .to_return(:status => 200, :body => fixture_rb)

          ts.cache_task_file(file)

          assert_requested(:get, "https://stubpuppet:8140/puppet/v3/file_content/tasks/choria/ls.rb?environment=production", :times => 1)

          expect(ts.task_file?(file)).to be(true)
        end

        it "should handle failures" do
          expect(ts.task_file?(file)).to be(false)

          stub_request(:get, "https://stubpuppet:8140/puppet/v3/file_content/tasks/choria/ls.rb?environment=production")
            .with(:headers => {"Accept" => "application/octet-stream"})
            .to_return(:status => 404, :body => "not found")

          expect do
            ts.cache_task_file(file)
          end.to raise_error("Failed to request task content /puppet/v3/file_content/tasks/choria/ls.rb?environment=production: 404: not found")

          assert_requested(:get, "https://stubpuppet:8140/puppet/v3/file_content/tasks/choria/ls.rb?environment=production", :times => 1)

          expect(ts.task_file?(file)).to be(false)
        end
      end

      describe "#task_file" do
        it "should fail if the dir does not exist" do
          File.expects(:directory?).with(ts.task_dir(file)).returns(false)
          expect(ts.task_file?(file)).to be(false)
        end

        it "should fail if the file does not exist" do
          File.expects(:directory?).with(ts.task_dir(file)).returns(true)
          File.expects(:exist?).with(ts.task_file_name(file)).returns(false)
          expect(ts.task_file?(file)).to be(false)
        end

        it "should fail if the file has the wrong size" do
          File.expects(:directory?).with(ts.task_dir(file)).returns(true)
          File.expects(:exist?).with(ts.task_file_name(file)).returns(true)
          ts.expects(:file_size).with(ts.task_file_name(file)).returns(1)
          expect(ts.task_file?(file)).to be(false)
        end

        it "should fail if the file has the wrong sha256" do
          File.expects(:directory?).with(ts.task_dir(file)).returns(true)
          File.expects(:exist?).with(ts.task_file_name(file)).returns(true)
          ts.expects(:file_size).with(ts.task_file_name(file)).returns(149)
          ts.expects(:file_sha256).with(ts.task_file_name(file)).returns("")

          expect(ts.task_file?(file)).to be(false)
        end

        it "should pass for correct files" do
          File.expects(:directory?).with(ts.task_dir(file)).returns(true)
          File.expects(:exist?).with(ts.task_file_name(file)).returns(true)
          ts.expects(:file_size).with(ts.task_file_name(file)).returns(149)
          ts.expects(:file_sha256).with(ts.task_file_name(file)).returns("f3b4821836cf7fe6fe17dfb2924ff6897eba43a44cc4cba0e0ed136b27934ede")

          expect(ts.task_file?(file)).to be(true)
        end
      end

      describe "#file_size" do
        it "should calculate the correct size" do
          expect(ts.file_size("spec/fixtures/tasks/choria_ls_metadata.json")).to eq(399)
        end
      end

      describe "#file_sha256" do
        it "should calculate the right sha256" do
          expect(ts.file_sha256("spec/fixtures/tasks/choria_ls_metadata.json")).to eq("d64078dedf92047339b14007d4fcdb93468ec763b024099a0e3a788d11b196da")
        end
      end

      describe "#task_metadata" do
        it "should fetch and decode the task metadata" do
          choria.expects(:puppet_server).returns(:target => "stubpuppet", :port => 8140)

          stub_request(:get, "https://stubpuppet:8140/puppet/v3/tasks/choria/ls?environment=production")
            .to_return(:status => 200, :body => fixture.to_json)

          expect(ts.task_metadata("choria::ls", "production")).to eq(fixture)
        end

        it "should handle failures correctly" do
          choria.expects(:puppet_server).returns(:target => "stubpuppet", :port => 8140)

          stub_request(:get, "https://stubpuppet:8140/puppet/v3/tasks/choria/ls?environment=production")
            .to_return(:status => 404, :body => "Could not find module 'choria'")

          expect do
            ts.task_metadata("choria::ls", "production")
          end.to raise_error("Failed to request task metadata: 404: Could not find module 'choria'")
        end
      end

      describe "#http_get" do
        it "should retrieve a file from the puppetserver" do
          choria.expects(:puppet_server).returns(:target => "stubpuppet", :port => 8140)

          stub_request(:get, "https://stubpuppet:8140/test")
            .with(:headers => {"Test-Header" => "true"})
            .to_return(:status => 200, :body => "Test OK")

          expect(ts.http_get("/test", "Test-Header" => true).body).to eq("Test OK")
        end
      end

      describe "#task_file_name" do
        it "should determine the correct file name" do
          expect(ts.task_file_name(fixture["files"][0])).to eq(File.join(cache, "f3b4821836cf7fe6fe17dfb2924ff6897eba43a44cc4cba0e0ed136b27934ede", "ls.rb"))
        end
      end

      describe "#task_dir" do
        it "should determine the correct directory" do
          expect(ts.task_dir(fixture["files"][0])).to eq(File.join(cache, "f3b4821836cf7fe6fe17dfb2924ff6897eba43a44cc4cba0e0ed136b27934ede"))
        end
      end

      describe "#parse_task" do
        it "should detect invalid tasks" do
          expect { ts.parse_task("fail") }.to raise_error("Invalid task name fail")
        end

        it "should parse correctly" do
          expect(ts.parse_task("choria::task")).to eq(["choria", "task"])
        end
      end
    end
  end
end

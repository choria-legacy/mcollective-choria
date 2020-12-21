require "spec_helper"
require "mcollective/util/choria"

module MCollective
  module Util
    describe Choria do
      let(:choria) { Choria.new(false) }

      describe "#credential_file" do
        it "should correctly return the configured options" do
          expect(choria.credential_file).to eq("")

          Config.instance.stubs(:pluginconf).returns(
            "nats.credentials" => "/foo"
          )

          expect(choria.credential_file).to eq("/foo")
        end
      end

      describe "#credential_file?" do
        it "should correctly detect the configured value" do
          expect(choria.credential_file?).to be(false)

          Config.instance.stubs(:pluginconf).returns(
            "nats.credentials" => "/foo"
          )

          expect(choria.credential_file?).to be(true)
        end
      end

      describe "#ngs" do
        it "should correctly report ngs settings" do
          expect(choria.ngs?).to be(false)

          Config.instance.stubs(:pluginconf).returns(
            "nats.credentials" => "/foo"
          )

          expect(choria.ngs?).to be(false)

          Config.instance.stubs(:pluginconf).returns(
            "nats.credentials" => "/foo",
            "nats.ngs" => "true"
          )

          expect(choria.ngs?).to be(true)
        end
      end

      describe "#file_security?" do
        it "should detect file security settings" do
          Config.instance.stubs(:pluginconf).returns(
            "security.provider" => "file"
          )

          expect(choria.file_security?).to be(true)
        end

        it "should be false otherwise" do
          Config.instance.stubs(:pluginconf).returns(
            "security.provider" => "puppet"
          )

          expect(choria.file_security?).to be(false)

          Config.instance.expects(:pluginconf).returns({})
          expect(choria.file_security?).to be(false)
        end
      end

      describe "#puppet_security?" do
        it "shouldd efault to puppet security settings" do
          expect(choria.puppet_security?).to be(true)
        end

        it "should detect puppet security settings" do
          Config.instance.stubs(:pluginconf).returns(
            "security.provider" => "puppet"
          )

          expect(choria.puppet_security?).to be(true)
        end

        it "should be false when not puppet" do
          Config.instance.stubs(:pluginconf).returns(
            "security.provider" => "file"
          )

          expect(choria.puppet_security?).to be(false)
        end
      end

      describe "#tasks_spool_dir" do
        it "should support windows" do
          Util.stubs(:windows?).returns(true)
          Util.stubs(:windows_prefix).returns("c:/nonexisting")

          expect(choria.tasks_spool_dir).to eq("c:/nonexisting/tasks-spool")
        end

        it "should non root on nix" do
          expect(choria.tasks_spool_dir).to eq(File.expand_path("~/.puppetlabs/mcollective/tasks-spool"))
        end

        it "should use aio paths for nix root" do
          Process.stubs(:uid).returns(0)
          expect(choria.tasks_spool_dir).to eq("/opt/puppetlabs/mcollective/tasks-spool")
        end
      end

      describe "#tasks_cache_dir" do
        it "should support windows" do
          Util.stubs(:windows?).returns(true)
          Util.stubs(:windows_prefix).returns("c:/nonexisting")

          expect(choria.tasks_cache_dir).to eq("c:/nonexisting/tasks-cache")
        end

        it "should support root users" do
          Process.stubs(:uid).returns(0)
          expect(choria.tasks_cache_dir).to eq("/opt/puppetlabs/mcollective/tasks-cache")
        end

        it "should support non root users" do
          expect(choria.tasks_cache_dir).to eq(File.expand_path("~/.puppetlabs/mcollective/tasks-cache"))
        end
      end

      describe "#tasks_support" do
        it "should create a support object that's correctly configured" do
          choria.stubs(:tasks_cache_dir).returns("/nonexisting/tasks-cache")
          support = choria.tasks_support
          expect(support.cache_dir).to eq("/nonexisting/tasks-cache")
        end
      end

      describe "#proxied_discovery?" do
        it "should correctly detect if proxied" do
          expect(choria.proxied_discovery?).to be(false)

          Config.instance.expects(:pluginconf).returns(
            "choria.discovery_host" => "9292"
          )
          expect(choria.proxied_discovery?).to be(true)

          Config.instance.expects(:pluginconf).returns(
            "choria.discovery_port" => "9292"
          ).twice
          expect(choria.proxied_discovery?).to be(true)

          Config.instance.expects(:pluginconf).returns(
            "choria.discovery_proxy" => "true"
          ).times(4)
          expect(choria.proxied_discovery?).to be(true)
        end
      end

      describe "#discovery_server" do
        it "should query SRV" do
          choria.stubs(:proxied_discovery?).returns(true)
          Config.instance.stubs(:pluginconf).returns(
            "choria.discovery_host" => "rspec.discovery",
            "choria.discovery_port" => "9292"
          )
          resolved = {:target => "rspec.puppet", :port => 8144}
          choria.expects(:try_srv).with(["_mcollective-discovery._tcp"], "rspec.discovery", "9292").returns(resolved)

          expect(choria.discovery_server).to eq(resolved)
        end
      end

      describe "#proxied_discovery?" do
        it "should correctly determine if proxied" do
          expect(choria.proxied_discovery?).to be(false)
          Config.instance.stubs(:pluginconf).returns("choria.discovery_proxy" => "true")
          expect(choria.proxied_discovery?).to be(true)
        end
      end

      describe "#have_ssl_files?" do
        before(:each) do
          choria.stubs(:client_public_cert).returns(File.expand_path("spec/fixtures/rip.mcollective.pem"))
          choria.stubs(:client_private_key).returns(File.expand_path("spec/fixtures/rip.mcollective.key"))
          choria.stubs(:ca_path).returns(File.expand_path("spec/fixtures/ca_crt.pem"))
        end

        it "should by default find all files" do
          expect(choria.have_ssl_files?).to be_truthy
        end

        it "fail if any files are missing" do
          choria.expects(:client_public_cert).returns("/nonexisting")
          expect(choria.have_ssl_files?).to be_falsey
        end
      end

      describe "#valid_certificate?" do
        it "should fail without a CA" do
          choria.expects(:ca_path).returns("/nonexisting").twice

          expect {
            choria.valid_certificate?("x", "badhostname")
          }.to raise_error("Cannot find or read the CA in /nonexisting, cannot verify public certificate")
        end

        it "should fail for CA missmatches" do
          choria.stubs(:ca_path).returns("spec/fixtures/other_ca.pem")
          expect(choria.valid_certificate?(File.read("spec/fixtures/rip.mcollective.pem"), "rip.mcollective")).to be_falsey

          choria.stubs(:ca_path).returns("spec/fixtures/ca_crt.pem")
          expect(choria.valid_certificate?(File.read("spec/fixtures/other.mcollective.pem"), "other.mcollective")).to be_falsey
        end

        it "should pass for valid cert/ca combos" do
          choria.stubs(:ca_path).returns("spec/fixtures/ca_crt.pem")
          expect(choria.valid_certificate?(File.read("spec/fixtures/rip.mcollective.pem"), "rip.mcollective")).to be_truthy
        end

        it "should check the identity when a remote signer is not used" do
          choria.stubs(:ca_path).returns("spec/fixtures/ca_crt.pem")
          expect(choria.remote_signer_configured?).to be(false)
          expect {
            choria.valid_certificate?(File.read("spec/fixtures/rip.mcollective.pem"), "other.mcollective")
          }.to raise_error("Could not parse certificate with subject /CN=rip.mcollective as it has no CN part, or name other.mcollective invalid")
          expect(choria.valid_certificate?(File.read("spec/fixtures/rip.mcollective.pem"), "rip.mcollective")).to be_truthy
        end

        it "should not check identity when a remote signer is used" do
          OpenSSL::SSL.expects(:verify_certificate_identity).never
          Config.instance.stubs(:pluginconf).returns("choria.security.request_signer.url" => "http://foo")
          choria.stubs(:ca_path).returns("spec/fixtures/ca_crt.pem")
          expect(choria.remote_signer_configured?).to be(true)
          choria.valid_certificate?(File.read("spec/fixtures/rip.mcollective.pem"), "other.mcollective")
        end
      end

      describe "#valid_intermediate_certificate?" do
        it "should fail for CA missmatches" do
          choria.stubs(:ca_path).returns("spec/fixtures/other_ca.pem")
          expect(choria.valid_certificate?(File.read("spec/fixtures/intermediate/chain-rip.mcollective.pem"), "rip.mcollective")).to be_falsey
        end

        it "should pass for valid client cert w/intermediate CA/ca combos" do
          choria.stubs(:ca_path).returns("spec/fixtures/intermediate/ca.pem")
          expect(choria.valid_certificate?(File.read("spec/fixtures/intermediate/chain-rip.mcollective.pem"), "rip.mcollective")).to be_truthy
        end
      end

      describe "#stats_port" do
        it "should be nil when the option is not present" do
          Config.instance.stubs(:pluginconf).returns({})
          expect(choria.stats_port).to be(nil)
        end

        it "should fail for non numbers" do
          Config.instance.stubs(:pluginconf).returns("choria.stats_port" => "a")
          expect { choria.stats_port }.to raise_error(/invalid value/)
        end

        it "should return valid numbers" do
          Config.instance.stubs(:pluginconf).returns("choria.stats_port" => "2")
          expect(choria.stats_port).to be(2)
        end
      end

      describe "#ssl_context" do
        it "should create a valid ssl context" do
          choria.stubs(:ca_path).returns("spec/fixtures/ca_crt.pem")
          choria.stubs(:client_public_cert).returns("spec/fixtures/rip.mcollective.pem")
          choria.stubs(:client_private_key).returns("spec/fixtures/rip.mcollective.key")

          context = choria.ssl_context

          expect(context.verify_mode).to be(OpenSSL::SSL::VERIFY_PEER)
          expect(context.ca_file).to eq("spec/fixtures/ca_crt.pem")
          expect(context.cert.subject.to_s).to eq("/CN=rip.mcollective")
          expect(context.key.to_pem).to eq(File.read("spec/fixtures/rip.mcollective.key"))
        end

        it "should create a valid ssl context with intermediate certs" do
          choria.stubs(:ca_path).returns("spec/fixtures/intermediate/ca.pem")
          choria.stubs(:client_public_cert).returns("spec/fixtures/intermediate/rip.mcollective.pem")
          choria.stubs(:client_private_key).returns("spec/fixtures/intermediate/rip.mcollective-key.pem")

          context = choria.ssl_context

          expect(context.verify_mode).to be(OpenSSL::SSL::VERIFY_PEER)
          expect(context.ca_file).to eq("spec/fixtures/intermediate/ca.pem")
          expect(context.cert.subject.to_s).to eq("/CN=rip.mcollective")
          expect(context.key.to_pem).to eq(File.read("spec/fixtures/intermediate/rip.mcollective-key.pem"))
        end
      end

      describe "#federation_collectives" do
        it "should correctly interpret federations config" do
          Config.instance.stubs(:pluginconf).returns("choria.federation.collectives" => "          ")
          expect(choria.federation_collectives).to eq([])

          Config.instance.stubs(:pluginconf).returns("choria.federation.collectives" => "net_a,net_b , net_c")
          expect(choria.federation_collectives).to eq(["net_a", "net_b", "net_c"])
        end

        it "should support environment variable setting" do
          Config.instance.stubs(:pluginconf).returns("choria.federation.collectives" => "net_a,net_b,net_c")
          choria.expects(:env_fetch).with("CHORIA_FED_COLLECTIVE", nil).returns("net_a, net_d")
          expect(choria.federation_collectives).to eq(["net_a", "net_d"])
        end
      end

      describe "#federated?" do
        it "should correctly report the config setting" do
          choria.expects(:federation_collectives).returns([])
          expect(choria.federated?).to be(false)

          choria.expects(:federation_collectives).returns(["fed_a", "fed_b"])
          expect(choria.federated?).to be(true)
        end
      end

      describe "#randomize_middleware_servers?" do
        it "should default to true" do
          Config.instance.stubs(:pluginconf).returns({})
          expect(choria.randomize_middleware_servers?).to be(true)
        end

        it "should be configurable" do
          Config.instance.stubs(:pluginconf).returns("choria.randomize_middleware_hosts" => "false")
          expect(choria.randomize_middleware_servers?).to be(false)
        end
      end

      describe "#should_use_srv?" do
        it "should default to on" do
          Config.instance.stubs(:pluginconf).returns({})
          expect(choria.should_use_srv?).to be(true)
        end

        it "should support common 'on' settings" do
          ["t", "true", "yes", "1"].each do |setting|
            Config.instance.stubs(:pluginconf).returns("choria.use_srv_records" => setting)
            expect(choria.should_use_srv?).to be(true)
          end
        end

        it "should support disabling SRV" do
          Config.instance.stubs(:pluginconf).returns("choria.use_srv_records" => "false")
          expect(choria.should_use_srv?).to be(false)
        end
      end

      describe "#pql_extract_certnames" do
        it "should extract all certname fields" do
          expect(
            choria.pql_extract_certnames([{"certname" => "one"}, {"certname" => "two"}, {"x" => "rspec"}])
          ).to eq(["one", "two"])
        end

        it "should ignore deacivated nodes" do
          expect(
            choria.pql_extract_certnames([{"certname" => "one", "deactivated" => "2016-09-12T18:57:51.700Z"}, {"certname" => "two"}])
          ).to eq(["two"])
        end
      end

      describe "#pql_query" do
        it "should query and parse" do
          choria.stubs(:facter_domain).returns("example.net")
          choria.expects(:http_get).with("/pdb/query/v4?query=nodes+%7B+%7D").returns(get = stub)
          choria.expects(:https).with({:target => "puppet", :port => "8081"}, true).returns(https = stub)
          https.expects(:request).with(get).returns([stub(:code => "200"), '{"rspec":1}'])

          expect(choria.pql_query("nodes { }")).to eq("rspec" => 1)
        end
      end

      describe "#has_option?" do
        it "should correctly detect available options" do
          Config.instance.stubs(:pluginconf).returns("choria.middleware_hosts" => "1.net:4222,2.net:4223")
          expect(choria.has_option?("choria.middleware_hosts")).to be(true)
          expect(choria.has_option?("choria.rspec")).to be(false)
        end
      end

      describe "#get_option" do
        before(:each) do
          Config.instance.stubs(:pluginconf).returns("choria.rspec" => "result")
        end

        it "should return the option verbatim if it exist" do
          expect(choria.get_option("choria.rspec")).to eq("result")
        end

        it "should support proc defaults" do
          expect(choria.get_option("choria.fail", -> { "lambda result" })).to eq("lambda result")
        end

        it "should support normal defaults" do
          expect(choria.get_option("choria.fail", "default result")).to eq("default result")
        end

        it "should raise without a default or option" do
          expect { choria.get_option("choria.fail") }.to raise_error("No plugin.choria.fail configuration option given")
        end
      end

      describe "#puppetdb_server" do
        it "should use x-puppet when db specific one is not set with the correct port" do
          choria.expects(:try_srv).with(["_x-puppet-db._tcp"], nil, nil).returns(:target => "db", :port => "8080")
          expect(choria.puppetdb_server).to eq(:target => "db", :port => "8080")
        end

        it "should use x-puppetdb when with the correct port" do
          choria.expects(:try_srv).with(["_x-puppet-db._tcp"], nil, nil).returns(:target => nil, :port => nil)
          choria.expects(:try_srv).with(["_x-puppet._tcp"], "puppet", "8081").returns(:target => "puppetserver", :port => "8084")

          expect(choria.puppetdb_server).to eq(:target => "puppetserver", :port => "8081")
        end

        it "should support defaults" do
          Config.instance.stubs(:pluginconf).returns("choria.puppetdb_host" => "puppet", "choria.puppetdb_port" => "8081")
          choria.expects(:try_srv).with(["_x-puppet-db._tcp"], nil, nil).returns(:target => nil, :port => nil)
          choria.expects(:try_srv).with(["_x-puppet._tcp"], "puppet", "8081").returns(:target => "puppet", :port => "8084")

          expect(choria.puppetdb_server).to eq(:target => "puppet", :port => "8081")
        end
      end

      describe "#try_srv" do
        it "should query for the correct names" do
          choria.expects(:query_srv_records).with(["rspec1"]).returns([:target => "rspec.host1", :port => "8081"])
          choria.expects(:query_srv_records).with(["rspec2"]).returns([:target => "rspec.host2", :port => "8082"])
          expect(choria.try_srv(["rspec1", "rspec2"], "h", "1")).to eq(:target => "rspec.host1", :port => "8081")
        end

        it "should support defaults" do
          choria.expects(:query_srv_records).returns([]).twice
          expect(choria.try_srv(["rspec1", "rspec2"], "rspec.host", "8080")).to eq(:target => "rspec.host", :port => "8080")
        end
      end

      describe "#server_resolver" do
        it "should support config" do
          Config.instance.stubs(:pluginconf).returns("choria.middleware_hosts" => "1.net:4222,2.net:4223, 3.net:4224 ")
          expect(choria.server_resolver("choria.middleware_hosts", ["srv_record"], "h", "1")).to eq(
            [
              ["1.net", "4222"],
              ["2.net", "4223"],
              ["3.net", "4224"]
            ]
          )
        end

        it "should support dns" do
          Config.instance.stubs(:pluginconf).returns({})
          choria.expects(:query_srv_records).with(
            ["_mcollective-server._tcp", "_x-puppet-mcollective._tcp"]
          ).returns(
            [{:target => "1.net", :port => "4222"}, {:target => "2.net", :port => "4223"}]
          )

          expect(choria.server_resolver("choria.middleware_hosts", ["_mcollective-server._tcp", "_x-puppet-mcollective._tcp"], "h", "1")).to eq(
            [
              ["1.net", "4222"],
              ["2.net", "4223"]
            ]
          )
        end

        it "should default" do
          Config.instance.stubs(:pluginconf).returns({})
          choria.stubs(:query_srv_records).returns([])
          expect(choria.server_resolver("choria.middleware_hosts", ["srv_record"], "1.net", "4222")).to eq(
            [["1.net", "4222"]]
          )
        end
      end

      describe "#remote_signer_configured?" do
        it "should detect when not configured or empty string" do
          expect(choria.remote_signer_configured?).to be(false)
          Config.instance.stubs(:pluginconf).returns(
            "choria.security.request_signer.url" => ""
          )
          expect(choria.remote_signer_configured?).to be(false)
        end

        it "should detect when configured" do
          Config.instance.stubs(:pluginconf).returns(
            "choria.security.request_signer.url" => "http://foo"
          )
          expect(choria.remote_signer_configured?).to be(true)
        end
      end

      describe "#federation_middleware_servers" do
        it "should resolve correctly" do
          choria.expects(:server_resolver).with(
            "choria.federation_middleware_hosts",
            ["_mcollective-federation_server._tcp", "_x-puppet-mcollective_federation._tcp"]
          ).returns([["1.net", "42"]])

          expect(choria.federation_middleware_servers).to eq([["1.net", "42"]])
        end
      end

      describe "#middleware_servers" do
        it "should support ngs" do
          Config.instance.stubs(:pluginconf).returns(
            "nats.credentials" => "/foo",
            "nats.ngs" => "true"
          )

          expect(choria.middleware_servers).to eq([["connect.ngs.global", "4222"]])

          Config.instance.stubs(:pluginconf).returns(
            "nats.credentials" => "/foo",
            "nats.ngs" => "true",
            "choria.middleware_hosts" => "x.net:4222"
          )
          expect(choria.middleware_servers).to eq([["x.net", "4222"]])
        end

        it "should support federations" do
          choria.expects(:federated?).returns(true)
          choria.expects(:federation_middleware_servers).returns([["f1.net", "4222"], ["f2.net", "4222"]])
          expect(choria.middleware_servers).to eq([["f1.net", "4222"], ["f2.net", "4222"]])
        end

        it "should only attempt federation lookups when federated" do
          choria.expects(:federated?).returns(false)
          choria.expects(:federation_middleware_servers).never
          choria.middleware_servers
        end

        it "should resolve correctly" do
          choria.expects(:server_resolver).with("choria.middleware_hosts", ["_mcollective-server._tcp", "_x-puppet-mcollective._tcp"], "puppet", "4222").returns([["1.net", "42"]])
          expect(choria.middleware_servers).to eq([["1.net", "42"]])
        end
      end

      describe "#srv_domain" do
        it "should support a configurable domain" do
          Config.instance.stubs(:pluginconf).returns("choria.srv_domain" => "r.net")
          choria.expects(:facter_domain).never
          expect(choria.srv_domain).to eq("r.net")
        end

        it "should support querying facter" do
          Config.instance.stubs(:pluginconf).returns({})
          choria.expects(:facter_domain).returns("r.net")
          expect(choria.srv_domain).to eq("r.net")
        end
      end

      describe "#srv_records" do
        it "should calcualte the right records" do
          choria.stubs(:srv_domain).returns("example.net")
          expect(choria.srv_records(["_1._tcp", "_2._tcp"]))
            .to eq(["_1._tcp.example.net", "_2._tcp.example.net"])
        end
      end

      describe "#query_srv_records" do
        it "should query the records and return answers" do
          resolver = stub
          choria.stubs(:resolver).returns(resolver)
          choria.stubs(:srv_domain).returns("example.net")

          answer1 = stub(:port => 1, :priority => 1, :weight => 1, :target => "one.example.net")
          result1 = {:port => 1, :priority => 1, :weight => 1, :target => "one.example.net"}
          answer2 = stub(:port => 2, :priority => 2, :weight => 1, :target => "two.example.net")
          result2 = {:port => 2, :priority => 2, :weight => 1, :target => "two.example.net"}

          resolver.expects(:getresources).with("_mcollective-server._tcp.example.net", Resolv::DNS::Resource::IN::SRV).returns([answer1])
          resolver.expects(:getresources).with("_x-puppet-mcollective._tcp.example.net", Resolv::DNS::Resource::IN::SRV).returns([answer2])

          expect(choria.query_srv_records(["_mcollective-server._tcp", "_x-puppet-mcollective._tcp"])).to eq([result1, result2])
        end

        it "should be possible to disable SRV support" do
          choria.expects(:should_use_srv?).returns(false)
          choria.expects(:srv_records).never
          expect(choria.query_srv_records(["_mcollective-server._tcp.example.net"])).to eq([])
        end
      end

      describe "#facter_cmd" do
        it "should check AIO path" do
          File.expects(:executable?).with("/opt/puppetlabs/bin/facter").returns(true)
          expect(choria.facter_cmd).to eq("/opt/puppetlabs/bin/facter")
        end

        it "should check the system PATH if not AIO" do
          File.expects(:executable?).with("/opt/puppetlabs/bin/facter").returns(false)
          File.expects(:executable?).with("/bin/facter").returns(false)
          File.expects(:executable?).with("/usr/bin/facter").returns(true)
          File.expects(:directory?).with("/usr/bin/facter").returns(false)

          choria.stubs(:env_fetch).with("PATHEXT", "").returns("")
          choria.stubs(:env_fetch).with("PATH", "").returns("/bin:/usr/bin")

          expect(choria.facter_cmd).to eq("/usr/bin/facter")
        end
      end

      context "when making certificates" do
        before(:each) do
          choria.stubs(:certname).returns("rspec.cert")
          choria.stubs(:ssl_dir).returns("/ssl")
          choria.stubs(:puppetca_server).returns(:target => "puppetca", :port => 8140)
        end

        describe "#waiting_for_cert?" do
          it "should correctly detect the waiting scenario" do
            choria.expects(:has_client_public_cert?).returns(true)
            expect(choria.waiting_for_cert?).to be_falsey

            choria.expects(:has_client_public_cert?).returns(false)
            choria.expects(:has_client_private_key?).returns(false)
            expect(choria.waiting_for_cert?).to be_falsey

            choria.expects(:has_client_public_cert?).returns(false)
            choria.expects(:has_client_private_key?).returns(true)
            expect(choria.waiting_for_cert?).to be_truthy
          end
        end

        describe "#proxy_discovery_query" do
          let(:req) { {"classes" => ["rpcutil"]} }

          before(:each) do
            choria.stubs(:check_ssl_setup).returns(true)
            choria.stubs(:discovery_server).returns(:target => "discovery", :port => 8082)
          end

          it "should request discovery and return found nodes" do
            res = {
              "status" => 200,
              "nodes" => [
                "web1.example.net",
                "web2.example.net"
              ]
            }

            stub_request(:get, "https://discovery:8082/v1/discover")
              .with(:headers => {"Content-Type" => "application/json"})
              .with(:body => req.to_json)
              .to_return(:status => 200, :body => res.to_json)

            expect(choria.proxy_discovery_query(req)).to eq(["web1.example.net", "web2.example.net"])
          end

          it "should handle failures" do
            res = {
              "status" => 400,
              "message" => "rspec error"
            }

            stub_request(:get, "https://discovery:8082/v1/discover")
              .with(:headers => {"Content-Type" => "application/json"})
              .with(:body => req.to_json)
              .to_return(:status => 400, :body => res.to_json)

            expect {
              choria.proxy_discovery_query(req)
            }.to raise_error('Failed to make request to Discovery Proxy: 400: {"status":400,"message":"rspec error"}')
          end
        end

        describe "#attempt_fetch_cert" do
          let(:headers) do
            {
              "Accept" => "text/plain",
              "User-Agent" => "Choria version %s http://choria.io" % Choria::VERSION,
              "Accept-Encoding" => "gzip;q=1.0,deflate;q=0.6,identity;q=0.3"
            }
          end

          it "should not overwrite existing certs" do
            choria.expects(:has_client_public_cert?).returns(true)
            choria.expects(:https).never
            expect(choria.attempt_fetch_cert).to be_truthy
          end

          it "should return false on failure" do
            choria.expects(:has_client_public_cert?).returns(false)
            stub_request(:get, "https://puppetca:8140/puppet-ca/v1/certificate/rspec.cert?environment=production")
              .with(:headers => headers)
              .to_return(:status => 404, :body => "success")

            File.expects(:open).never

            expect(choria.attempt_fetch_cert).to be_falsey
          end

          it "should write the retrieved cert" do
            cert = File.read("spec/fixtures/rip.mcollective.pem")
            file = StringIO.new
            File.expects(:open).with("/ssl/certs/rspec.cert.pem", "w", 0o0644).yields(file)

            choria.expects(:has_client_public_cert?).returns(false)
            stub_request(:get, "https://puppetca:8140/puppet-ca/v1/certificate/rspec.cert?environment=production")
              .with(:headers => headers)
              .to_return(:status => 200, :body => cert)

            expect(choria.attempt_fetch_cert).to be_truthy
            expect(file.string).to eq(cert)
          end
        end

        describe "#request_cert" do
          let(:key) { OpenSSL::PKey::RSA.new(File.read("spec/fixtures/rip.mcollective.key")) }
          let(:csr) { choria.create_csr("rspec.cert", "mcollective", key) }

          before(:each) do
            choria.stubs(:write_key).returns(key)
            choria.stubs(:write_csr).with(key).returns(csr.to_pem)
          end

          it "should submit the cert to puppet" do
            stub_request(:put, "https://puppetca:8140/puppet-ca/v1/certificate_request/rspec.cert?environment=production")
              .with(:headers => {"Content-Type" => "text/plain"}, :body => csr.to_pem)
              .to_return(:status => 200, :body => "success")

            expect(choria.request_cert).to be_truthy
          end

          it "should correctly handle failures" do
            stub_request(:put, "https://puppetca:8140/puppet-ca/v1/certificate_request/rspec.cert?environment=production")
              .with(:headers => {"Content-Type" => "text/plain"}, :body => csr.to_pem)
              .to_return(:status => [500, "Internal Server Error"], :body => "rspec fail")

            expect {
              choria.request_cert
            }.to raise_error("Failed to request certificate from puppetca:8140: 500: Internal Server Error: rspec fail")
          end
        end

        describe "#write_csr" do
          it "should not overwrite existing CSRs" do
            choria.expects(:has_csr?).returns(true)
            expect {
              choria.write_csr(:x)
            }.to raise_error("Refusing to overwrite existing CSR in /ssl/certificate_requests/rspec.cert.pem")
          end

          it "should write the right CSR" do
            key = OpenSSL::PKey::RSA.new(File.read("spec/fixtures/rip.mcollective.key"))
            file = StringIO.new
            scsr = choria.create_csr("rspec.cert", "mcollective", key)

            File.expects(:open).with("/ssl/certificate_requests/rspec.cert.pem", "w", 0o0644).yields(file)
            choria.expects(:create_csr).with("rspec.cert", "mcollective", key).returns(scsr)

            csr = choria.write_csr(key)
            expect(csr).to eq(scsr.to_pem)
            expect(file.string).to eq(csr)
          end
        end

        describe "#create_csr" do
          it "should create a valid CSR" do
            key = OpenSSL::PKey::RSA.new(File.read("spec/fixtures/rip.mcollective.key"))
            csr = choria.create_csr("rspec.cert", "rspec", key)
            expect(csr.version).to be(0)
            expect(csr.public_key.to_pem).to eq(key.public_key.to_pem)
            expect(csr.subject.to_s).to eq("/CN=rspec.cert/OU=rspec")
          end
        end

        describe "#write_key" do
          it "should not overwrite existing keys" do
            choria.stubs(:has_client_private_key?).returns(true)

            expect {
              choria.write_key
            }.to raise_error("Refusing to overwrite existing key in /ssl/private_keys/rspec.cert.pem")
          end

          it "should write a 4096 bit pem" do
            key = OpenSSL::PKey::RSA.new(File.read("spec/fixtures/rip.mcollective.key"))
            file = StringIO.new

            File.expects(:open).with("/ssl/private_keys/rspec.cert.pem", "w", 0o0640).yields(file)
            choria.expects(:create_rsa_key).with(4096).returns(key)

            expect(choria.write_key).to be(key)
            expect(file.string).to eq(key.to_pem)
          end
        end
      end

      describe "#make_ssl_dirs" do
        it "should make the right dirs" do
          choria.stubs(:ssl_dir).returns("/ssl")
          FileUtils.expects(:mkdir_p).with("/ssl", :mode => 0o0771)
          FileUtils.expects(:mkdir_p).with("/ssl/certificate_requests", :mode => 0o0755)
          FileUtils.expects(:mkdir_p).with("/ssl/certs", :mode => 0o0755)
          FileUtils.expects(:mkdir_p).with("/ssl/public_keys", :mode => 0o0755)
          FileUtils.expects(:mkdir_p).with("/ssl/private_keys", :mode => 0o0750)
          FileUtils.expects(:mkdir_p).with("/ssl/private", :mode => 0o0750)

          choria.make_ssl_dirs
        end

        it "should support the file security provider" do
          Config.instance.stubs(:pluginconf).returns(
            "security.provider" => "file"
          )

          FileUtils.expects(:mkdir_p).never

          choria.make_ssl_dirs
        end
      end

      describe "#expand_path" do
        it "should expand paths" do
          expect(choria.expand_path("~")).to eq(File.expand_path("~"))
        end

        it "should not expand empty paths" do
          expect(choria.expand_path("")).to eq("")
        end
      end

      describe "#csr_path" do
        it "should get the right path in ssl_dir" do
          choria.expects(:ssl_dir).returns("/ssl")
          choria.expects(:certname).returns("rspec")
          expect(choria.csr_path).to eq("/ssl/certificate_requests/rspec.pem")
        end

        it "should support the file security provider" do
          Config.instance.stubs(:pluginconf).returns(
            "security.provider" => "file"
          )

          expect(choria.csr_path).to eq("")
        end
      end

      describe "#ca_path" do
        it "should get the right path in ssl_dir" do
          choria.expects(:ssl_dir).returns("/ssl")
          expect(choria.ca_path).to eq("/ssl/certs/ca.pem")
        end

        it "should support the file security provider" do
          Config.instance.stubs(:pluginconf).returns(
            "security.provider" => "file",
            "security.file.ca" => "~/ssl/ca.pem"
          )

          expect(choria.ca_path).to eq(File.expand_path("~/ssl/ca.pem"))
        end
      end

      describe "#client_public_cert" do
        it "should get the right path in ssl_dir" do
          choria.expects(:ssl_dir).returns("/ssl")
          choria.expects(:certname).returns("rspec")
          expect(choria.client_public_cert).to eq("/ssl/certs/rspec.pem")
        end

        it "should support file security provider" do
          Config.instance.stubs(:pluginconf).returns(
            "security.provider" => "file",
            "security.file.certificate" => "~/ssl/rspec.pem"
          )

          expect(choria.client_public_cert).to eq(File.expand_path("~/ssl/rspec.pem"))
        end
      end

      describe "#client_private_key" do
        it "should get the right path in ssl_dir" do
          choria.expects(:ssl_dir).returns("/ssl")
          choria.expects(:certname).returns("rspec")
          expect(choria.client_private_key).to eq("/ssl/private_keys/rspec.pem")
        end

        it "should support the file security provider" do
          Config.instance.stubs(:pluginconf).returns(
            "security.provider" => "file",
            "security.file.key" => "~/ssl/rspec-key.pem"
          )

          expect(choria.client_private_key).to eq(File.expand_path("~/ssl/rspec-key.pem"))
        end
      end

      describe "#certname" do
        it "should take identity for root" do
          Process.expects(:uid).returns(0)
          expect(choria.certname).to eq("rspec_identity")
        end

        it "should support USER environment" do
          choria.expects(:env_fetch).with("USER", "rspec_identity").returns("rip")
          choria.expects(:env_fetch).with("MCOLLECTIVE_CERTNAME", "rip.mcollective").returns("rip.mcollective")
          expect(choria.certname).to eq("rip.mcollective")
        end

        it "should be overridable by MCOLLECTIVE_CERTNAME" do
          choria.expects(:env_fetch).with("USER", "rspec_identity").returns("rspec_identity")
          choria.expects(:env_fetch).with("MCOLLECTIVE_CERTNAME", "rspec_identity.mcollective").returns("rip.mcollective")
          expect(choria.certname).to eq("rip.mcollective")
        end
      end

      describe "#ssl_dir" do
        it "should support windows" do
          Util.expects(:windows?).returns(true)
          choria.expects(:puppet_setting).with(:ssldir).returns('C:\ProgramData\PuppetLabs\puppet\etc\ssl')
          expect(choria.ssl_dir).to eq('C:\ProgramData\PuppetLabs\puppet\etc\ssl')
        end

        it "should support root on unix" do
          Util.expects(:windows?).returns(false)
          Process.expects(:uid).returns(0)
          choria.expects(:puppet_setting).with(:ssldir).returns("/etc/puppetlabs/puppet/ssl")
          expect(choria.ssl_dir).to eq("/etc/puppetlabs/puppet/ssl")
        end

        it "should support users" do
          Util.expects(:windows?).returns(false)
          Process.expects(:uid).returns(500)
          File.expects(:expand_path).with("~/.puppetlabs/etc/puppet/ssl").returns("/rspec/.puppetlabs/etc/puppet/ssl")
          expect(choria.ssl_dir).to eq("/rspec/.puppetlabs/etc/puppet/ssl")
        end

        it "should be configurable" do
          Config.instance.stubs(:pluginconf).returns(
            "choria.ssldir" => "/nonexisting/ssl"
          )

          choria.expects(:puppet_setting).never

          expect(choria.ssl_dir).to eq("/nonexisting/ssl")
        end

        it "should memoize the result" do
          Util.expects(:windows?).returns(true).once
          choria.expects(:puppet_setting).with(:ssldir).returns('C:\ProgramData\PuppetLabs\puppet\etc\ssl').once
          expect(choria.ssl_dir).to eq('C:\ProgramData\PuppetLabs\puppet\etc\ssl')
          expect(choria.ssl_dir).to eq('C:\ProgramData\PuppetLabs\puppet\etc\ssl')
        end
      end

      describe "#puppetca_server" do
        it "should query SRV" do
          Config.instance.stubs(:pluginconf).returns(
            "choria.puppetca_host" => "rspec.puppetca",
            "choria.puppetca_port" => "8141"
          )
          resolved = {:target => "rspec.puppetca", :port => 8144}
          choria.expects(:try_srv).with(["_x-puppet-ca._tcp", "_x-puppet._tcp"], "rspec.puppetca", "8141").returns(resolved)

          expect(choria.puppetca_server).to eq(resolved)
        end
      end

      describe "#puppet_server" do
        it "should query SRV" do
          Config.instance.stubs(:pluginconf).returns(
            "choria.puppetserver_host" => "rspec.puppet",
            "choria.puppetserver_port" => "8140"
          )
          resolved = {:target => "rspec.puppet", :port => 8144}
          choria.expects(:try_srv).with(["_x-puppet._tcp"], "rspec.puppet", "8140").returns(resolved)

          expect(choria.puppet_server).to eq(resolved)
        end
      end

      describe "#check_ssl_setup" do
        before(:each) do
          PluginManager.stubs(:[]).with("security_plugin").returns(stub(:initiated_by => :client))
          choria.stubs(:client_public_cert).returns(File.expand_path("spec/fixtures/rip.mcollective.pem"))
          choria.stubs(:ca_path).returns(File.expand_path("spec/fixtures/ca_crt.pem"))
        end

        it "should fail on clients running as root" do
          Process.stubs(:uid).returns(0)
          expect { choria.check_ssl_setup }.to raise_error("The Choria client cannot be run as root")
        end

        it "should fail if files are missing" do
          choria.expects(:have_ssl_files?).returns(false)
          expect { choria.check_ssl_setup }.to raise_error("Not all required SSL files exist")
        end

        it "should fail if the cert is not signed by the CA" do
          choria.expects(:have_ssl_files?).returns(true)
          pub_cert = File.read(choria.client_public_cert)
          choria.expects(:valid_certificate?).with(pub_cert, choria.certname).raises("rspec fail")
          expect { choria.check_ssl_setup }.to raise_error("The public certificate was not signed by the configured CA")
        end

        it "should fail if the certname isnt the same as configured" do
          choria.expects(:have_ssl_files?).returns(true)
          choria.expects(:valid_certificate?).returns("rspec")
          expect { choria.check_ssl_setup }.to raise_error("The certname rspec found in %s does not match the configured certname of %s" % [
            choria.client_public_cert, choria.certname
          ])
        end

        it "should pass when ok" do
          choria.expects(:have_ssl_files?).returns(true)
          choria.expects(:valid_certificate?).returns(choria.certname)
          expect(choria.check_ssl_setup).to be(true)
        end
      end

      describe "#https" do
        it "should support anonymous connections" do
          choria.stubs(:has_client_public_cert?).returns(false)
          choria.stubs(:has_client_private_key?).returns(false)
          choria.stubs(:ca_path).returns(File.expand_path("spec/fixtures/ca_crt.pem"))

          h = choria.https(:target => "puppet", :port => "8140")

          expect(h.use_ssl?).to be_truthy
          expect(h.verify_mode).to be(OpenSSL::SSL::VERIFY_PEER)
          expect(h.cert).to be_nil
          expect(h.key).to be_nil
          expect(h.ca_file).to eq(choria.ca_path)
        end

        it "should support unverified connections" do
          choria.stubs(:client_public_cert).returns(File.expand_path("spec/fixtures/rip.mcollective.pem"))
          choria.stubs(:client_private_key).returns(File.expand_path("spec/fixtures/rip.mcollective.key"))
          choria.stubs(:has_ca?).returns(false)

          h = choria.https(:target => "puppet", :port => "8140")

          expect(h.use_ssl?).to be_truthy
          expect(h.verify_mode).to be(OpenSSL::SSL::VERIFY_NONE)
          expect(h.cert.subject.to_s).to eq("/CN=rip.mcollective")
          expect(h.key.to_pem).to eq(File.read(choria.client_private_key))
        end

        it "should create a valid http client" do
          choria.stubs(:client_public_cert).returns(File.expand_path("spec/fixtures/rip.mcollective.pem"))
          choria.stubs(:client_private_key).returns(File.expand_path("spec/fixtures/rip.mcollective.key"))
          choria.stubs(:ca_path).returns(File.expand_path("spec/fixtures/ca_crt.pem"))

          h = choria.https(:target => "puppet", :port => "8140")

          expect(h.use_ssl?).to be_truthy
          expect(h.verify_mode).to be(OpenSSL::SSL::VERIFY_PEER)
          expect(h.cert.subject.to_s).to eq("/CN=rip.mcollective")
          expect(h.ca_file).to eq(choria.ca_path)
          expect(h.key.to_pem).to eq(File.read(choria.client_private_key))
        end

        it "should support forcing puppet ssl" do
          choria.expects(:check_ssl_setup).returns(true)
          choria.https({:target => "puppet", :port => "8140"}, true)
        end
      end
    end
  end
end

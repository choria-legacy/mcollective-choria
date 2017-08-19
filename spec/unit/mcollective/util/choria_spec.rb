require "spec_helper"
require "mcollective/util/choria"

module MCollective
  module Util
    describe Choria do
      let(:choria) { Choria.new("production", nil, false) }
      let(:parsed_app) { JSON.parse(File.read("spec/fixtures/sample_app.json")) }

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
            choria.valid_certificate?("x")
          }.to raise_error("Cannot find or read the CA in /nonexisting, cannot verify public certificate")
        end

        it "should fail for CA missmatches" do
          choria.stubs(:ca_path).returns("spec/fixtures/other_ca.pem")
          expect(choria.valid_certificate?(File.read("spec/fixtures/rip.mcollective.pem"))).to be_falsey

          choria.stubs(:ca_path).returns("spec/fixtures/ca_crt.pem")
          expect(choria.valid_certificate?(File.read("spec/fixtures/other.mcollective.pem"))).to be_falsey
        end

        it "should pass for valid cert/ca combos" do
          choria.stubs(:ca_path).returns("spec/fixtures/ca_crt.pem")
          expect(choria.valid_certificate?(File.read("spec/fixtures/rip.mcollective.pem"))).to be_truthy
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
        it "should default to false" do
          Config.instance.stubs(:pluginconf).returns({})
          expect(choria.randomize_middleware_servers?).to be(false)
        end

        it "should be configurable" do
          Config.instance.stubs(:pluginconf).returns("choria.randomize_middleware_hosts" => "true")
          expect(choria.randomize_middleware_servers?).to be(true)
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
          expect(choria.get_option("choria.fail", ->() { "lambda result" })).to eq("lambda result")
        end

        it "should support normal defaults" do
          expect(choria.get_option("choria.fail", "default result")).to eq("default result")
        end

        it "should raise without a default or option" do
          expect { choria.get_option("choria.fail") }.to raise_error("No plugin.choria.fail configuration option given")
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
            stub_request(:get, "https://puppetca:8140/puppet-ca/v1/certificate/rspec.cert")
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
            stub_request(:get, "https://puppetca:8140/puppet-ca/v1/certificate/rspec.cert")
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
      end

      describe "#csr_path" do
        it "should get the right path in ssl_dir" do
          choria.expects(:ssl_dir).returns("/ssl")
          choria.expects(:certname).returns("rspec")
          expect(choria.csr_path).to eq("/ssl/certificate_requests/rspec.pem")
        end
      end

      describe "#ca_path" do
        it "should get the right path in ssl_dir" do
          choria.expects(:ssl_dir).returns("/ssl")
          expect(choria.ca_path).to eq("/ssl/certs/ca.pem")
        end
      end

      describe "#client_public_cert" do
        it "should get the right path in ssl_dir" do
          choria.expects(:ssl_dir).returns("/ssl")
          choria.expects(:certname).returns("rspec")
          expect(choria.client_public_cert).to eq("/ssl/certs/rspec.pem")
        end
      end

      describe "#client_private_key" do
        it "should get the right path in ssl_dir" do
          choria.expects(:ssl_dir).returns("/ssl")
          choria.expects(:certname).returns("rspec")
          expect(choria.client_private_key).to eq("/ssl/private_keys/rspec.pem")
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
          choria.expects(:valid_certificate?).with(pub_cert).raises("rspec fail")
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

      describe "#fetch_environment" do
        before(:each) do
          choria.stubs(:client_public_cert).returns(File.expand_path("spec/fixtures/rip.mcollective.pem"))
          choria.stubs(:client_private_key).returns(File.expand_path("spec/fixtures/rip.mcollective.key"))
          choria.stubs(:ca_path).returns(File.expand_path("spec/fixtures/ca_crt.pem"))
          choria.stubs(:puppet_server).returns(:target => "puppet", :port => "8140")
        end

        it "should fetch the right environment over https expecting JSON" do
          stub_request(:get, "https://puppet:8140/puppet/v3/environment/production")
            .with(:headers => {"Accept" => "application/json"})
            .to_return(:status => [500, "Internal Server Error"], :body => "failed")

          expect {
            choria.fetch_environment
          }.to raise_error("Failed to make request to Puppet: 500: Internal Server Error: failed")
        end

        it "should report error for non 200 replies" do
          stub_request(:get, "https://puppet:8140/puppet/v3/environment/production")
            .to_return(:status => 200, :body => File.read("spec/fixtures/sample_app.json"))

          expect(choria.fetch_environment).to eq(parsed_app)
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

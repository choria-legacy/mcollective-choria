require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      class Nodes
        describe TerraformNodes do
          let(:nodes) { TerraformNodes.new }
          let(:bad_fixture) { File.read(File.expand_path("spec/fixtures/playbooks/terraform_string.json")) }
          let(:fixture) { File.read(File.expand_path("spec/fixtures/playbooks/terraform_list.json")) }

          before(:each) do
            nodes.from_hash(
              "statefile" => __FILE__,
              "terraform" => "/usr/local/bin/terraform",
              "output" => "rspec"
            )
          end

          describe "#valid_hostname?" do
            it "should correctly detect certnames" do
              expect(nodes.valid_hostname?("example.net")).to be_truthy
              expect(nodes.valid_hostname?("node1 example.net")).to be_falsey
            end
          end

          describe "#validate_configuration!" do
            it "should check terraform is executable" do
              File.expects(:executable?).with("/usr/local/bin/terraform").returns(false)
              expect { nodes.validate_configuration! }.to raise_error("The supplied terraform path /usr/local/bin/terraform is not executable")
            end

            it "should check the statefile exist" do
              File.stubs(:executable?).returns(true)
              File.expects(:readable?).with("/nonexisting").returns(false)

              nodes.from_hash(
                "statefile" => "/nonexisting",
                "terraform" => "/usr/local/bin/terraform"
              )

              expect { nodes.validate_configuration! }.to raise_error("The terraform statefile /nonexisting is not readable")
            end

            it "should check a output is given" do
              File.stubs(:executable?).returns(true)
              nodes.from_hash(
                "statefile" => __FILE__,
                "terraform" => "/usr/local/bin/terraform"
              )
              expect { nodes.validate_configuration! }.to raise_error("An output name is needed")
            end

            it "should validate everything is shell safe" do
              File.stubs(:executable?).returns(true)
              Validator.expects(:validate).with("/usr/local/bin/terraform", :shellsafe)
              Validator.expects(:validate).with(__FILE__, :shellsafe)
              Validator.expects(:validate).with("rspec", :shellsafe)
              nodes.validate_configuration!
            end

            it "should accept good input" do
              File.stubs(:executable?).returns(true)
              nodes.validate_configuration!
            end
          end

          describe "#from_hash" do
            it "should look for terraform in path if not given" do
              nodes.expects(:choria).returns(choria = stub)
              choria.expects(:which).with("terraform").returns("/nonexisting/terraform")
              nodes.from_hash({})
              expect(nodes.instance_variable_get("@terraform")).to eq("/nonexisting/terraform")
            end
          end

          describe "#tf_output" do
            it "should execute the right command" do
              Shell.expects(:new).with("/usr/local/bin/terraform output -state %s -json rspec 2>&1" % [__FILE__]).raises("rspec")

              expect { nodes.tf_output }.to raise_error("rspec")
            end

            it "should fail for non 0 exit codes" do
              Shell.expects(:new).returns(stub(:runcommand => nil, :stdout => "error", :status => stub(:exitstatus => 1)))

              expect { nodes.tf_output }.to raise_error("Terraform exited with code 1: error")
            end

            it "should return the stdout text" do
              Shell.expects(:new).returns(stub(:runcommand => nil, :stdout => fixture, :status => stub(:exitstatus => 0)))
              expect(nodes.tf_output).to eq(fixture)
            end
          end

          describe "#output_data" do
            it "should only accept list type data" do
              nodes.expects(:tf_output).returns(bad_fixture)
              expect { nodes.output_data }.to raise_error("Only terraform outputs of type list is supported")
            end

            it "should validate found hostnames" do
              nodes.expects(:tf_output).returns(fixture)
              nodes.expects(:valid_hostname?).with("ec2-52-57-66-150.eu-central-1.compute.amazonaws.com").returns(true)
              nodes.expects(:valid_hostname?).with("ec2-52-57-74-75.eu-central-1.compute.amazonaws.com").returns(true)
              nodes.expects(:valid_hostname?).with("ec2-52-29-231-0.eu-central-1.compute.amazonaws.com").returns(true)
              nodes.expects(:valid_hostname?).with("ec2-52-57-73-4.eu-central-1.compute.amazonaws.com").returns(false)
              expect { nodes.output_data }.to raise_error("ec2-52-57-73-4.eu-central-1.compute.amazonaws.com is not a valid hostname")
            end

            it "should return the found data" do
              nodes.expects(:tf_output).returns(fixture)
              expect(nodes.output_data).to eq(
                [
                  "ec2-52-57-66-150.eu-central-1.compute.amazonaws.com",
                  "ec2-52-57-74-75.eu-central-1.compute.amazonaws.com",
                  "ec2-52-29-231-0.eu-central-1.compute.amazonaws.com",
                  "ec2-52-57-73-4.eu-central-1.compute.amazonaws.com"
                ]
              )
            end
          end
        end
      end
    end
  end
end

require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    class Playbook
      describe TemplateUtil do
        let(:playbook) { stub }
        let(:tu) do
          x = Object.new
          x.extend(TemplateUtil)
          x.instance_variable_set("@playbook", playbook)
          x
        end

        describe "#__template_process_string" do
          it "should fail for absent playbooks" do
            tu.instance_variable_set("@playbook", nil)
            expect { tu.__template_process_string("") }.to raise_error("Playbook is not accessible")
          end

          it "should lookup inputs, metadata and nodes, previous_task and preserve data type" do
            tu.expects(:__template_resolve).with("input", "x").returns(1)
            tu.expects(:__template_resolve).with("inputs", "y").returns(1)
            tu.expects(:__template_resolve).with("nodes", "x").returns(["value1", "value2"])
            tu.expects(:__template_resolve).with("metadata", "x").returns(2)
            tu.expects(:__template_resolve).with("previous_task", "msg").returns("rspec_message")

            expect(tu.__template_process_string("{{{ input.x }}}")).to eq(1)
            expect(tu.__template_process_string("{{{ inputs.y }}}")).to eq(1)
            expect(tu.__template_process_string("{{{ nodes.x}}}")).to eq(["value1", "value2"])
            expect(tu.__template_process_string("{{{metadata.x}}}")).to eq(2)
            expect(tu.__template_process_string("{{{previous_task.msg}}}")).to eq("rspec_message")
          end

          it "should support dates" do
            tu.expects(:__template_resolve).with("date", "%Y%m%dT%H%M%S%z").returns("20161229T134508+0100")
            expect(tu.__template_process_string("{{{date(%Y%m%dT%H%M%S%z)}}}")).to eq("20161229T134508+0100")

            tu.expects(:__template_resolve).with("utc_date", "%Y%m%dT%H%M%S%z").returns("20161229T124726+0000")
            expect(tu.__template_process_string("{{{ utc_date('%Y%m%dT%H%M%S%z') }}}")).to eq("20161229T124726+0000")
          end

          it "should support uuids" do
            tu.expects(:__template_resolve).with("uuid", "").returns(SSL.uuid("rspec"))
            expect(tu.__template_process_string("{{{uuid}}}")).to eq("479d1982-120a-5ba8-8664-1f16a6504371")
          end

          it "should process strings until just the template part is found" do
            tu.expects(:__template_resolve).with("nodes", "x").returns(["value1", "value2"])
            tu.expects(:__template_resolve).with("input", "x").returns("value1" => "value2")
            tu.expects(:__template_resolve).with("uuid", "").returns("479d1982-120a-5ba8-8664-1f16a6504371")

            expect(tu.__template_process_string("nodes: {{{ nodes.x }}} input: {{{ input.x }}} uuid: {{{ uuid }}}"))
              .to eq("nodes: value1, value2 input: {\"value1\":\"value2\"} uuid: 479d1982-120a-5ba8-8664-1f16a6504371")
          end
        end

        describe "#__template_resolve" do
          it "should support previous_task" do
            playbook.expects(:previous_task).with("rspec").returns("value")
            expect(tu.__template_resolve("previous_task", "rspec")).to eq("value")
          end

          it "should support inputs" do
            playbook.expects(:input_value).with("rspec").returns("value").twice
            expect(tu.__template_resolve("input", "rspec")).to eq("value")
            expect(tu.__template_resolve("inputs", "rspec")).to eq("value")
          end

          it "should support nodes" do
            playbook.expects(:discovered_nodes).with("rspec").returns(["value"])
            expect(tu.__template_resolve("nodes", "rspec")).to eq(["value"])
          end

          it "should support metadata" do
            playbook.expects(:metadata_item).with("rspec").returns("value")
            expect(tu.__template_resolve("metadata", "rspec")).to eq("value")
          end

          it "should fail for unknown types of data" do
            expect { tu.__template_resolve("rspec", "rspec").to eq("value") }.to raise_error("Do not know how to process data of type rspec")
          end

          it "should support dates" do
            now = Time.now
            Time.expects(:now).returns(now)
            expect(tu.__template_resolve("date", "%Y%m%dT%H%M%S%z")).to eq(now.strftime("%Y%m%dT%H%M%S%z"))
          end

          it "should support utc dates" do
            now = Time.now
            Time.expects(:now).returns(now)
            expect(tu.__template_resolve("utc_date", "%Y%m%dT%H%M%S%z")).to eq(now.utc.strftime("%Y%m%dT%H%M%S%z"))
          end

          it "should support uuids" do
            SSL.expects(:uuid).returns("479d1982-120a-5ba8-8664-1f16a6504371")
            expect(tu.__template_resolve("uuid", "")).to eq("479d1982-120a-5ba8-8664-1f16a6504371")
          end
        end

        describe "#t" do
          it "should resolve strings" do
            tu.expects(:__template_process_string).with("rspec")
            tu.t("rspec")
          end

          it "should traverse hashes" do
            tu.expects(:__template_process_string).with("value").returns("parsed value")
            expect(tu.t("key" => "value")).to eq("key" => "parsed value")
          end

          it "should traverse arrays" do
            tu.expects(:__template_process_string).with("value1").returns("parsed value1")
            tu.expects(:__template_process_string).with("value2").returns("parsed value2")
            expect(tu.t(["value1", "value2"])).to eq(["parsed value1", "parsed value2"])
          end

          it "should otherwise return data verbatim" do
            tu.expects(:__template_process_string).never
            expect(tu.t(:rspec)).to be(:rspec)
          end
        end
      end
    end
  end
end

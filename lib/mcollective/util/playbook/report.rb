module MCollective
  module Util
    class Playbook
      class Report
        attr_reader :timestamp

        def initialize(playbook)
          @playbook = playbook
          @logs = []
          @timestamp = Time.now.utc
          @version = 1
          @nodes = {}
          @tasks = []
          @success = false
          @final = false

          @metrics = {
            "start_time" => @timestamp,
            "end_time" => @timestamp,
            "run_time" => 0,
            "task_count" => 0,
            "task_types" => {}
          }

          @inputs = {
            "static" => {},
            "dynamic" => []
          }
        end

        def finalize(success, fail_msg=nil)
          return(to_report) if @final

          @success = success
          @fail_message = fail_msg

          store_playbook_metadata
          store_static_inputs
          store_dynamic_inputs
          store_node_groups
          store_task_results
          calculate_metrics

          @final = true

          to_report
        end

        def to_report
          {
            "report" => {
              "version" => @version,
              "timestamp" => @timestamp,
              "success" => @success,
              "playbook_error" => @fail_message
            },

            "playbook" => {
              "name" => @playbook_name,
              "version" => @playbook_version
            },

            "inputs" => @inputs,
            "nodes" => @nodes,
            "tasks" => @tasks,
            "metrics" => @metrics,
            "logs" => @logs
          }
        end

        def calculate_metrics
          @metrics["end_time"] = Time.now.utc
          @metrics["run_time"] = @metrics["end_time"] - @metrics["start_time"]
          @metrics["task_count"] = @tasks.size

          @tasks.each do |task|
            @metrics["task_types"][task["type"]] ||= {
              "count" => 0,
              "total_time" => 0,
              "pass" => 0,
              "fail" => 0
            }

            metrics = @metrics["task_types"][task["type"]]

            metrics["count"] += 1
            metrics["total_time"] += task["run_time"]
            task["success"] ? metrics["pass"] += 1 : metrics["fail"] += 1
          end

          @metrics
        end

        def store_task_results
          @playbook.task_results.each do |result|
            @tasks << {
              "type" => result.task_type,
              "set" => result.set,
              "description" => result.description,
              "start_time" => result.start_time.utc,
              "end_time" => result.end_time.utc,
              "run_time" => result.run_time,
              "ran" => result.ran,
              "msg" => result.msg,
              "success" => result.success
            }
          end

          @tasks
        end

        def store_playbook_metadata
          @playbook_name = @playbook.name
          @playbook_version = @playbook.version
        end

        def store_node_groups
          @playbook.nodes.each do |key|
            @nodes[key] = @playbook.discovered_nodes(key)
          end
        end

        def store_dynamic_inputs
          @inputs["dynamic"] = @playbook.dynamic_inputs
        end

        def store_static_inputs
          @playbook.static_inputs.each do |key|
            @inputs["static"][key] = @playbook.input_value(key)
          end
        end

        def append_log(time, level, from, msg)
          @logs << {
            "time" => time.utc,
            "level" => level.to_s,
            "from" => from.strip,
            "msg" => msg
          }
        end
      end
    end
  end
end

module MCollective
  module Util
    class TasksSupport
      class CLI
        class JSONFormatter
          attr_reader :out

          def initialize(cli, verbose=false, out=STDOUT)
            @cli = cli
            @verbose = verbose
            @out = out

            @started = false
            @in_results = false
            @in_stats = false
            @first_item = true
          end

          def start
            return if @started

            @started = true
            @in_results = true

            out.puts '{"items": ['
          end

          def end_results
            return unless @in_results

            @in_results = false
            out.puts "],"
          end

          # (see DefaultFormatter.print_task_summary)
          def print_task_summary(taskid, names, callers, completed, running, task_not_known, wrapper_failure, success, fails, runtime, rpcstats)
            end_results

            stats = {
              "names" => names,
              "callers" => callers,
              "completed" => completed,
              "running" => running,
              "task_not_known" =>  task_not_known,
              "wrapper_failure" => wrapper_failure,
              "success" => success,
              "failed" => fails,
              "average_runtime" => runtime / (running + completed),
              "noresponses" => rpcstats.noresponsefrom
            }

            summary = {
              "nodes" => rpcstats.discovered_nodes.size,
              "taskid" => taskid,
              "completed" => stats["completed"] == rpcstats.discovered_nodes.size,
              "success" => success == rpcstats.discovered_nodes.size
            }

            out.puts '"stats":'
            out.puts stats.to_json
            out.puts ","
            out.puts '"summary":'

            out.puts summary.to_json
            out.puts "}"
          end

          # (see DefaultFormatter.print_rpc_stats)
          def print_rpc_stats(stats)
            end_results
          end

          # (see DefaultFormatter.print_result)
          def print_result(result)
            start

            result = result.results

            item = {
              "host" => result[:sender]
            }

            result[:data].each do |k, v|
              item[k.to_s] = v
            end

            begin
              item["stdout"] = JSON.parse(item["stdout"])
              item["stdout"] = item["stdout"].delete("_output") if item["stdout"]["_output"]
            rescue # rubocop:disable Lint/HandleExceptions
            end

            out.puts "," unless @first_item

            out.puts item.to_json

            @first_item = false
          end

          # (see DefaultFormatter.print_result_metadata)
          def print_result_metadata(status)
            print_result(status)
          end
        end
      end
    end
  end
end

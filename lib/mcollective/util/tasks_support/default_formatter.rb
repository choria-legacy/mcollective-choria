module MCollective
  module Util
    class TasksSupport
      class CLI
        class DefaultFormatter
          attr_reader :out

          def initialize(cli, verbose=false, out=$stdout)
            @cli = cli
            @verbose = verbose
            @out = out
          end

          # Prints the summary of a task over a number of machines
          #
          # @param taskid [String] the task id
          # @param names [Array<String>] list of unique task names seen in the estate
          # @param callers [Array<String>] list of unique callers seen in the estate
          # @param completed [Integer] nodes that completed the task - success or fails
          # @param running [Integer] nodes still running the task
          # @param task_not_known [Integer] nodes where the task is unknown
          # @param wrapper_failure [Integer] nodes where the wrapper executable failed to launch
          # @param success [Integer] nodes that completed the task succesfully
          # @param fails [Integer] nodes that did not complete the task succesfully
          # @param runtime [Float] total run time across all nodes
          # @param rpcstats [RPC::Stats] the stats from the RPC client that fetched the statusses
          def print_task_summary(taskid, names, callers, completed, running, task_not_known, wrapper_failure, success, fails, runtime, rpcstats)
            if callers.size > 1 || names.size > 1
              out.puts
              out.puts("%s received more than 1 task name or caller name for this task, this should not happen" % Util.colorize(:red, "WARNING"))
              out.puts("happen in normal operations and might indicate forged requests were made or cache corruption.")
              out.puts
            end

            out.puts("Summary for task %s" % [Util.colorize(:bold, taskid)])
            out.puts
            out.puts("                       Task Name: %s" % names.join(","))
            out.puts("                          Caller: %s" % callers.join(","))
            out.puts("                       Completed: %s" % (completed > 0 ? Util.colorize(:green, completed) : Util.colorize(:yellow, completed)))
            out.puts("                         Running: %s" % (running > 0 ? Util.colorize(:yellow, running) : Util.colorize(:green, running)))
            out.puts("                    Unknown Task: %s" % Util.colorize(:red, task_not_known)) if task_not_known > 0
            out.puts("                 Wrapper Failure: %s" % Util.colorize(:red, wrapper_failure)) if wrapper_failure > 0
            out.puts
            out.puts("                      Successful: %s" % (success > 0 ? Util.colorize(:green, success) : Util.colorize(:red, success)))
            out.puts("                          Failed: %s" % (fails > 0 ? Util.colorize(:red, fails) : fails))
            out.puts
            out.puts("                Average Run Time: %.2fs" % [runtime / (running + completed)])

            if rpcstats.noresponsefrom.empty?
              out.puts
              out.puts rpcstats.no_response_report
            end

            if running > 0
              out.puts
              out.puts("%s nodes are still running, use 'mco tasks status %s' to check on them later" % [Util.colorize(:bold, running), taskid])
            end
          end

          # Prints the RPC stats for a request
          #
          # @param stats [RPC::Stats] request stats
          def print_rpc_stats(stats)
            out.puts stats.report("Task Stats", false, @verbose)
          end

          # Prints an individual result
          #
          # @param result [RPC::Result]
          def print_result(result)
            status = result[:data]
            stdout_text = status[:stdout] || ""

            unless @verbose
              begin
                stdout_text = JSON.parse(status[:stdout])
                stdout_text.delete("_error")
                stdout_text = stdout_text.to_json
                stdout_text = nil if stdout_text == "{}"
              rescue # rubocop:disable Lint/SuppressedException
              end
            end

            if result[:statuscode] != 0
              out.puts("%-40s %s" % [
                Util.colorize(:red, result[:sender]),
                Util.colorize(:yellow, result[:statusmsg])
              ])

              out.puts("   %s" % stdout_text) if stdout_text
              out.puts("   %s" % status[:stderr]) unless ["", nil].include?(status[:stderr])
              out.puts
            elsif result[:statuscode] == 0 && @verbose
              out.puts(result[:sender])
              out.puts("   %s" % stdout_text) if stdout_text
              out.puts("   %s" % status[:stderr]) unless ["", nil].include?(status[:stderr])
              out.puts
            end
          end

          # Prints metadata for an individual result
          #
          # @param status [RPC::Reply] the individual task status to print
          def print_result_metadata(status)
            result = status.results

            if [0, 1].include?(result[:statuscode])
              if result[:data][:exitcode] == 0
                out.puts("  %-40s %s" % [result[:sender], Util.colorize(:green, result[:data][:exitcode])])
              else
                out.puts("  %-40s %s" % [result[:sender], Util.colorize(:red, result[:data][:exitcode])])
              end

              out.puts("    %s by %s at %s" % [
                Util.colorize(:bold, result[:data][:task]),
                result[:data][:callerid],
                Time.at(result[:data][:start_time]).utc.strftime("%F %T")
              ])

              out.puts("    completed: %s runtime: %s stdout: %s stderr: %s" % [
                result[:data][:completed] ? Util.colorize(:bold, "yes") : Util.colorize(:yellow, "no"),
                Util.colorize(:bold, "%.2f" % result[:data][:runtime]),
                result[:data][:stdout].empty? ? Util.colorize(:yellow, "no") : Util.colorize(:bold, "yes"),
                result[:data][:stderr].empty? ? Util.colorize(:bold, "no") : Util.colorize(:red, "yes")
              ])
            elsif result[:statuscode] == 3
              out.puts("  %-40s %s" % [result[:sender], Util.colorize(:yellow, "Unknown Task")])
            else
              out.puts("  %-40s %s" % [result[:sender], Util.colorize(:yellow, result[:statusmsg])])
            end

            out.puts
          end
        end
      end
    end
  end
end

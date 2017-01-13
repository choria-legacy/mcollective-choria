module MCollective
  module Util
    class Playbook
      class Tasks
        class Mcollective_assertTask < Base
          def startup_hook
            @properties = {}
            @nodes = []
            @action = nil
            @pre_sleep = 10
            @expression = []
            @pre_slept = false
          end

          def from_hash(data)
            @nodes = data.fetch("nodes", [])
            @action = data["action"]
            @properties = data.fetch("properties", {})
            @pre_sleep = Integer(data.fetch("pre_sleep", 10))
            @expression = data["expression"] || []
            @description = data.fetch("description", "Wait until %s matches %s %s %s" % [@action, @expression[0], @expression[1], @expression[2]])

            self
          end

          def validate_configuration!
            raise("An expression should be 3 items exactly") unless @expression.size == 3
          end

          def perform_pre_sleep
            return if @pre_slept || @pre_sleep <= 0

            Log.info("Sleeping %d seconds before check" % [@pre_sleep])

            sleep(@pre_sleep)

            @pre_slept = true
          end

          def mcollective_task
            rpc = Tasks::McollectiveTask.new
            rpc.from_hash(
              "description" => @description,
              "nodes" => @nodes,
              "action" => @action,
              "properties" => @properties,
              "silent" => true
            )
          end

          def evaluate(left, operator, right)
            invert = false

            if operator =~ /^\!\s*(.+)/
              invert = true
              operator = $1
            end

            result = case operator
                     when "<"
                       left < right
                     when ">"
                       left > right
                     when ">="
                       left >= right
                     when "<="
                       left <= right
                     when "==", "="
                       left == right
                     when "=~"
                       !!Regexp.new(right, true).match(left)
                     when "in"
                       right.include?(left)
                     else
                       raise("Unknown operator %s encountered, cannot assert state" % operator)
                     end

            invert ? !result : result
          end

          def check_results(results)
            left, operator, right = @expression
            failed = false

            results.each do |result|
              unless result["data"].include?(left)
                Log.warn("Result from %s does not have the %s item" % [result["sender"], left])
                failed = true
                next
              end

              unless evaluate(result["data"][left], operator, right)
                Log.warn("Result from %s does not match the expression" % [result["sender"]])
                failed = true
              end
            end

            if failed
              [false, "Not all nodes matched expression %s %s %s" % [left, operator, right], results]
            else
              [true, "All nodes matched expression %s %s %s" % [left, operator, right], results]
            end
          end

          def run
            perform_pre_sleep

            success, msg, results = mcollective_task.run

            return([false, "Request %s failed: %s" % [@action, msg], []]) unless success

            check_results(results)
          rescue
            msg = "Could not create request for %s: %s: %s" % [@action, $!.class, $!.to_s]
            Log.debug(msg)
            Log.debug($!.backtrace.join("\t\n"))

            [false, msg, []]
          end
        end
      end
    end
  end
end

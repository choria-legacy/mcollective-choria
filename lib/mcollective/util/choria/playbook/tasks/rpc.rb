module MCollective
  module Util
    class Choria
      class Playbook
        class Tasks
          class Rpc
            attr_accessor :failure_critical, :post, :tries, :try_sleep, :on_fail

            attr_reader :agent, :action, :properties, :batch_size, :batch_sleep_time
            attr_reader :limit_targets, :limit_method, :limit_seed, :nodes

            attr_reader :playbook, :success, :ran, :output, :fail_reason

            def initialize(playbook)
              @playbook = playbook
              @success = false

              @_configured = false
              @ran = false
              @fail_reason = "unknown failure reason"
            end

            def raise_and_record(klass, msg)
              @fail_reason = msg
              raise(klass, msg, caller)
            end

            def to_s
              "#<RPC: %s#%s>" % [agent, action]
            end

            # much of this belongs in Playbook::RPC I suspect
            # on_fail handling but that belongs one level up
            def run!
              raise("RPC task %s#%s already ran" % [agent, action]) if ran

              @ran = true
              results = nil
              soft_error = false

              playbook.debug("Starting RPC task for %s#%s" % [agent, action])

              (1..tries).each_with_index do |try|
                errored = false

                begin
                  results = client.unchecked_call(action, properties) do |result|
                    playbook.info("Node %s responded: %s" % [result[:sender], result[:statusmsg]]) if result[:statuscode] == 0
                  end
                rescue
                  errored = true
                p client.ok?
                p errored
                p (client.ok? && !errored)
                p try
                p tries

                  playbook.warn("RPC call %s#%s failed: %s: %s" % [agent, action, $!.class, $!.to_s])
                end

                break if client.ok? && !errored

                p "boo"

                if try == tries
                  if failure_critical
                    playbook.warn("Critical failure condition after %d tries of %s#%s" % [try, agent, action])
                    raise_and_record(RPCError, "RPC %s#%s failed after %d tries" % [agent, action, try])
                  else
                    playbook.warn("Non critical failure condition after %d tries of %s#%s" % [try, agent, action])
                    soft_error = true
                  end
                else
                  playbook.info("Sleeping %d seconds till next try after %d/%d tries of %s#%s" % [try_sleep, try, tries, agent, action])
                  sleep(try_sleep)
                end
              end

              @success = true # if it was a critical failure exception would have raised
              @output = [results, client.stats.dup]
            ensure
              playbook.debug("Completed RPC task %s#%s soft failure: %s success: %s" % [agent, action, soft_error, success])
            end

            def t(msg)
              playbook.t(msg)
            end

            def client
              return @_client if @_client

              raise_and_record("Cannot configure a client because the task has not been configured yet") unless @_configured

              @_client = playbook.rpc_client(agent)
              @_client.discover(:nodes => nodes) if nodes

              @_client.batch_size = batch_size if batch_size
              @_client.batch_sleep_time = batch_sleep_time if batch_sleep_time

              @_client.limit_targets = limit_targets if limit_targets
              @_client.limit_method = limit_method.intern
              @_client.limit_seed = limit_seed if limit_seed

              @_client
            end

            def parse_action(action)
              action.match(/^(?<agent>[a-z][a-zA-Z0-9]*)\.(?<action>[a-z][a-zA-Z0-9]*)$/)
            end

            def from_source(task)
              task = t(task)

              parsed = parse_action(task["action"])

              raise_and_record("Invalid action %s, should be in the form agent.action" % task["action"]) unless parsed

              @agent = parsed[:agent]
              @action = parsed[:action]
              @properties = task.fetch("properties", {})
              @nodes = task.fetch("nodes", nil)
              @filter = task.fetch("filter", nil)

              @batch_size = task.fetch("batch_size", nil)
              @batch_sleep_time = task.fetch("batch_sleep_time", nil)

              @limit_targets = task.fetch("limit_targets", nil)
              @limit_method = task.fetch("limit_method", "random")
              @limit_seed = task.fetch("limit_seed", nil)

              @failure_critical = task.fetch("failure_critical", true)
              @tries = task.fetch("tries", 1)
              @try_sleep = task.fetch("try_sleep", 10)
              @on_fail = task.fetch("on_fail", nil)
              @post = task.fetch("post", [])

              @_configured = true
            end
          end
        end
      end
    end
  end
end

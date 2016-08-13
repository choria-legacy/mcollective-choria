module MCollective
  module Util
    class Choria
      class Playbook
        class Tasks
          class Helper
            attr_accessor :failure_critical, :post, :tries, :try_sleep, :on_fail

            attr_reader :agent, :helper, :properties

            attr_reader :playbook, :success, :ran, :output, :fail_reason

            def initialize(playbook)
              @playbook = playbook
              @success = false

              @_configured = false
              @ran = false
            end

            def raise_and_record(klass, msg)
              @fail_reason = msg
              raise(klass, msg, caller)
            end

            def to_s
              "#<Helper: %s>" % [helper || "unconfigured"]
            end

            # much of this belongs in Playbook::RPC I suspect
            # tries handling belong on level up
            # on_fail handling belongs one level up
            # failure_critical handling belongs one level up
            # already ran belongs one level up, this run! should *just* run not all this shit
            def run!
              raise("Helper task %s#%s already ran" % [agent, helper]) if ran

              @ran = true
              results = nil
              soft_error = false

              playbook.debug("Starting Helper task for %s#%s" % [agent, helper])

              (1..tries).each_with_index do |try|
                errored = false

                begin
                  klass = helper_class(agent)
                  raise("Unknown helper class for agent %s" % agent) unless klass
                  klass.new(playbook).send(helper.intern, properties)
                rescue
                  errored = true
                  playbook.warn("Helper call %s#%s failed: %s: %s" % [agent, helper, $!.class, $!.to_s])
                end

                break if !errored

                if try == tries
                  if failure_critical
                    playbook.warn("Critical failure condition after %d tries of %s#%s" % [try, agent, helper])
                    raise_and_record(TaskError, "Helper %s#%s failed after %d tries" % [agent, helper, try])
                  else
                    playbook.warn("Non critical failure condition after %d tries of %s#%s" % [try, agent, helper])
                    soft_error = true
                  end
                else
                  playbook.info("Sleeping %d seconds till next try after %d/%d tries of %s#%s" % [try_sleep, try, tries, agent, helper])
                  sleep(try_sleep)
                end
              end

              @success = true # if it was a critical failure exception would have raised
              @output = nil
            ensure
              playbook.debug("Completed Helper task %s#%s soft failure: %s success: %s" % [agent, helper, soft_error, success])
            end

            def t(msg)
              playbook.t(msg)
            end

            def helper_class(name)
              MCollective::Helpers.const_get(name.capitalize.intern)
            rescue
              nil
            end

            def parse_action(action)
              action.match(/^(?<agent>[a-z][a-zA-Z0-9]*)\.(?<helper>[a-z][a-zA-Z0-9_]*)$/)
            end

            def from_source(task)
              task = t(task)

              parsed = parse_action(task["name"])

              raise_and_record("Invalid name %s, should be in the form agent.helper_name" % task["name"]) unless parsed

              @agent = parsed[:agent]
              @helper = parsed[:helper]
              @properties = task.fetch("properties", {})
              @nodes = task.fetch("nodes", nil)

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


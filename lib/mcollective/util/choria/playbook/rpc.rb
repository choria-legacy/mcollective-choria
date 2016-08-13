module MCollective
  module Util
    class Choria
      class Playbook
        class RPC
          attr_reader :playbook

          def initialize(agent, playbook)
            @_agent = agent
            @_client = new_client(agent)
            @playbook = playbook
          end

          def checked_call(action, arguments={}, &blk)
            results = unchecked_call(action, arguments, &blk)

            unless ok?
              raise(CommsError, "RPC call %s#%s failed" % [@_agent, action])
            end

            results
          rescue
            raise(CommsError, "RPC call encountered a critical error: %s: %s" % [$!.class, $!.to_s])
          end

          def unchecked_call(action, arguments={}, &blk)
            playbook.debug("Calling %s#%s with %s" % [@_agent, action, arguments.inspect])

            results = @_client.send(action, arguments.dup)

            if block_given?
              results.each do |result|
                yield(result)
              end
            end

            unless ok?
              log_failures(results)
            end

            results
          end

          def all_responded?
            stats.noresponsefrom.empty?
          end

          def all_passed?
            stats.failcount == 0
          end

          def ok?
            all_responded? && all_passed?
          end

          def log_failures(results)
            return if ok?

            unless all_responded?
              stats.noresponsefrom.each do |node|
                playbook.warn("Did not receive a response from %s" % node)
              end
            end

            unless all_passed?
              results.each do |result|
                next if result.results[:statuscode] == 0
                playbook.warn("Failed response from %s: %s: %s" % [result[:sender], result[:statuscode], result[:statusmsg]])
              end
            end
          end

          def method_missing(method, *args, &blk)
            @_client.send(method, *args, &blk)
          end

          def new_client(agent)
            options = {:verbose      => false,
                       :config       => Util.config_file_for_user,
                       :progress_bar => false,
                       :filter       => Util.empty_filter}

            MCollective::RPC::Client.new(agent.to_s, :configfile => options[:config], :options => options)
          end
        end
      end
    end
  end
end

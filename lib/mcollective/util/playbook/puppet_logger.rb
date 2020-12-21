require "mcollective/logger/console_logger"

module MCollective
  module Util
    class Playbook
      class Puppet_Logger < Logger::Console_logger
        attr_writer :scope

        def initialize(playbook)
          @playbook = playbook
          @report = playbook.report

          super()
        end

        def start
          set_level(@playbook.loglevel.intern)
        end

        def log(level, from, msg, normal_output=$stderr, last_resort_output=$stderr)
          return unless should_show?(level)

          logmethod = case level
                      when :info
                        :notice
                      when :warn
                        :warning
                      when :error
                        :err
                      when :fatal
                        :crit
                      else
                        :debug
                      end

          if @scope
            Puppet::Util::Log.log_func(@scope, logmethod, [msg])
          else
            Puppet.send(logmethod, msg)
          end
        end

        def should_show?(level)
          return true unless level == :info

          !caller(2..5).grep(/playbook/).empty?
        end
      end
    end
  end
end

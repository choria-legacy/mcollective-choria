require "mcollective/logger/console_logger"

module MCollective
  module Util
    class Playbook
      class Playbook_Logger < Logger::Console_logger
        def initialize(playbook)
          @playbook = playbook
          @report = playbook.report

          super()
        end

        def start
          set_level(@playbook.loglevel.intern)
        end

        def log(level, from, msg, normal_output=STDERR, last_resort_output=STDERR)
          if @playbook.loglevel != "debug"
            if should_show?
              console_from = "%s#%-25s" % [@playbook.name, @playbook.context]
            else
              level = :debug
            end
          end

          if @known_levels.index(level) >= @known_levels.index(@active_level)
            r_time = Time.now
            s_time = r_time.strftime("%H:%M:%S")

            @report.append_log(r_time, level, from, msg)

            normal_output.puts("%s %s: %s %s" % [colorize(level, level[0].capitalize), s_time, console_from, msg])
          end
        rescue
          last_resort_output.puts("%s: %s" % [level, msg])
        end

        def should_show?
          !caller(1..5).grep(/playbook/).empty?
        end
      end
    end
  end
end

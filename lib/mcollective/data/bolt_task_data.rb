module MCollective
  module Data
    class Bolt_task_data < Base
      activate_when do
        Util::Choria.new.tasks_support.tasks_compatible?
      end

      query do |taskid|
        tasks = Util::Choria.new.tasks_support

        begin
          status = tasks.task_status(taskid)

          result[:known] = true

          if status["task"]
            tasks.task_status(taskid).each do |item, value|
              value = value.utc.to_i if value.is_a?(Time)
              value = value.to_json if value.is_a?(Hash)

              result[item.intern] = value
            end

            result[:start_time] = result[:start_time].to_i
          end
        rescue
          Log.debug("Task %s was not found, returning default data. Error was: %s" % [taskid, $!.to_s])
        end
      end
    end
  end
end

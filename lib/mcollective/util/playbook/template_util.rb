module MCollective
  module Util
    class Playbook
      module TemplateUtil
        # Recursively parse a data structure seeking strings that might contain templates
        #
        # Template strings look like `{{{scope.key}}}` where scope is one of `input`, `metadata`,
        # `nodes` and the key is some item contained in those scopes like a named node list.
        #
        # You'll generally mix this into a class you wish to use it in, that class should have
        # a `@playbook` variable set which is an instance of `Playbook`
        #
        # @param data [Object] data structure to traverse
        # @return [Object] deep cloned copy of the structure with strings parsed
        def t(data)
          data = Marshal.load(Marshal.dump(data))

          if data.is_a?(String)
            __template_process_string(data)
          elsif data.is_a?(Hash)
            data.each do |k, v|
              data[k] = t(v)
            end

            data
          elsif data.is_a?(Array)
            data.map do |v|
              t(v)
            end
          else
            data
          end
        end

        def __template_resolve(type, item)
          Log.debug("Resolving template data for %s.%s" % [type, item])

          case type
          when "input", "inputs"
            @playbook.input_value(item)
          when "nodes"
            @playbook.discovered_nodes(item)
          when "metadata"
            @playbook.metadata_item(item)
          when "previous_task"
            @playbook.previous_task(item)
          when "date"
            Time.now.strftime(item)
          when "utc_date"
            Time.now.utc.strftime(item)
          when "elapsed_time"
            @playbook.report.elapsed_time
          when "uuid"
            SSL.uuid
          else
            raise("Do not know how to process data of type %s" % type)
          end
        end

        def __template_process_string(string)
          raise("Playbook is not accessible") unless @playbook

          front = '{{2,3}\s*'
          back = '\s*}{2,3}'

          data_regex = Regexp.new("%s%s%s" % [front, '(?<type>input(s*)|metadata|nodes)\.(?<item>[a-zA-Z0-9\_\-]+)', back])
          date_regex = Regexp.new("%s%s%s" % [front, '(?<type>date|utc_date)\(\s*["\']*(?<format>.+?)["\']*\s*\)', back])
          task_regex = Regexp.new("%s%s%s" % [front, '(?<type>previous_task)\.(?<item>(success|description|msg|message|data|runtime))', back])
          singles_regex = Regexp.new("%s%s%s" % [front, "(?<type>uuid|elapsed_time)", back])

          combined_regex = Regexp.union(data_regex, date_regex, task_regex, singles_regex)

          if req = string.match(/^#{data_regex}$/)
            __template_resolve(req["type"], req["item"])
          elsif req = string.match(/^#{date_regex}$/)
            __template_resolve(req["type"], req["format"])
          elsif req = string.match(/^#{task_regex}$/)
            __template_resolve(req["type"], req["item"])
          elsif req = string.match(/^#{singles_regex}$/)
            __template_resolve(req["type"], "")
          else
            string.gsub(/#{combined_regex}/) do |part|
              value = __template_process_string(part)

              if value.is_a?(Array)
                value.join(", ")
              elsif value.is_a?(Hash)
                value.to_json
              else
                value
              end
            end
          end
        end
      end
    end
  end
end

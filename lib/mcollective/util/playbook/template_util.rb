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
        # a `@playbook` variable set which is an instnace of `Playbook`
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
          case type
          when "input"
            @playbook.input_value(item)
          when "nodes"
            @playbook.discovered_nodes(item)
          when "metadata"
            @playbook.metadata_item(item)
          else
            raise("Do not know how to process data of type %s" % type)
          end
        end

        def __template_process_string(string)
          raise("Playbook is not accessible") unless @playbook

          part_regex = '{{{\s*(?<type>input|metadata|nodes)\.(?<name>[a-zA-Z0-9\_\-]+)\s*}}}'

          if req = string.match(/^#{part_regex}$/)
            Log.debug("Resolving template data for %s.%s" % [req["type"], req["name"]])

            __template_resolve(req["type"], req["name"])
          else
            string.gsub(/#{part_regex}/) do |part|
              __template_process_string(part)
            end
          end
        end
      end
    end
  end
end

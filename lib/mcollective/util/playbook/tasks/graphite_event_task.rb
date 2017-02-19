require "uri"

module MCollective
  module Util
    class Playbook
      class Tasks
        class Graphite_eventTask < Base
          def run
            webhook_task.run
          end

          def request
            {
              "what" => @what,
              "tags" => @tags.join(","),
              "when" => Time.now.to_i,
              "data" => @data
            }
          end

          def webhook_task
            webhook = Tasks::WebhookTask.new(@playbook)

            webhook.from_hash(
              "description" => @description,
              "headers" => @headers,
              "uri" => @graphite,
              "method" => "POST",
              "data" => request
            )
          end

          def validate_configuration!
            raise("The 'what' property is required") unless @what
            raise("The 'data' property is required") unless @data
            raise("The 'graphite' property is required") if @graphite == ""
            raise("'tags' should be an array") unless @tags.is_a?(Array)
            raise("'headers' should be a hash") unless @headers.is_a?(Hash)
            raise("The graphite url should be either http or https") unless ["http", "https"].include?(@uri.scheme)
          end

          def from_hash(properties)
            @what = properties["what"]
            @data = properties["data"]
            @graphite = properties.fetch("graphite", "")
            @headers = properties.fetch("headers", {})
            @tags = properties.fetch("tags", ["choria"])
            @uri = URI.parse(@graphite)
          end
        end
      end
    end
  end
end

require "cgi"
require "json"

module MCollective
  module Util
    class Playbook
      class Tasks
        class SlackTask < Base
          def validate_configuration!
            raise("A channel is required") unless @channel
            raise("Message text is required") unless @text
            raise("A bot token is required") unless @token
          end

          def from_hash(data)
            @channel = data["channel"]
            @text = data["text"]
            @token = data["token"]
            @color = data.fetch("color", "#ffa449")
            @username = data.fetch("username", "Choria")
            @icon = "http://choria.io/img/slack-48x48.png"

            self
          end

          def choria
            @_choria ||= Util::Choria.new(false)
          end

          def attachments
            [
              "fallback" => @text,
              "color" => @color,
              "text" => @text,
              "pretext" => "Task: %s" % @description,
              "mrkdwn_in" => ["text"],
              "footer" => "Choria Playbooks",
              "fields" => [
                {
                  "title" => "user",
                  "value" => PluginManager["security_plugin"].callerid,
                  "short" => true
                },
                {
                  "title" => "playbook",
                  "value" => @playbook.name,
                  "short" => true
                }
              ]
            ]
          end

          def run
            https = choria.https(:target => "slack.com", :port => 443)
            path = "/api/chat.postMessage?token=%s&username=%s&channel=%s&icon_url=%s&attachments=%s" % [
              CGI.escape(@token),
              CGI.escape(@username),
              CGI.escape(@channel),
              CGI.escape(@icon),
              CGI.escape(attachments.to_json)
            ]

            resp, data = https.request(choria.http_get(path))
            data = JSON.parse(data || resp.body)

            if resp.code == "200" && data["ok"]
              Log.info("Successfully sent message to slack channel %s" % [@channel])
              [true, "Message submitted to slack channel %s" % [@channel], [data]]
            else
              Log.warn("Failed to send message to slack channel %s: %s" % [@channel, data["error"]])
              [false, "Failed to send message to slack channel %s: %s" % [@channel, data["error"]], [data]]
            end
          rescue
            msg = "Could not publish slack message to channel %s: %s: %s" % [@channel, $!.class, $!.to_s]
            Log.debug(msg)
            Log.debug($!.backtrace.join("\t\n"))

            [false, msg, []]
          end
        end
      end
    end
  end
end

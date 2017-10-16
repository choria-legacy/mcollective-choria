require "uri"
require "cgi"
require "json"

module MCollective
  module Util
    class Playbook
      class Tasks
        class WebhookTask < Base
          USER_AGENT = "Choria Playbooks http://choria.io".freeze

          attr_reader :verify_ssl

          def validate_configuration!
            raise("A uri is required") unless @uri
            raise("Only GET and POST is supported as methods") unless ["GET", "POST"].include?(@method)
          end

          def from_hash(data)
            @headers = data.fetch("headers", {})
            @data = data.fetch("data", {})
            @uri = data["uri"]
            @method = data.fetch("method", "POST").upcase
            @request_id = SSL.uuid
            @verify_ssl = Util.str_to_bool(data.fetch("verify_ssl", true))

            self
          end

          def create_uri
            uri = URI.parse(@uri)

            if @method == "GET"
              query = Array(uri.query)

              @data.each do |k, v|
                query << "%s=%s" % [CGI.escape(k), CGI.escape(v.to_s)]
              end

              uri.query = query.join("&") unless query.empty?
            end

            uri
          end

          def http_get_request(uri)
            headers = {
              "User-Agent" => USER_AGENT,
              "X-Choria-Request-ID" => @request_id
            }.merge(@headers)

            Net::HTTP::Get.new(uri.request_uri, headers)
          end

          def http_post_request(uri)
            headers = {
              "Content-Type" => "application/json",
              "User-Agent" => USER_AGENT,
              "X-Choria-Request-ID" => @request_id
            }.merge(@headers)

            req = Net::HTTP::Post.new(uri.request_uri, headers)
            req.body = @data.to_json
            req
          end

          def http_request(uri)
            return http_get_request(uri) if @method == "GET"
            return http_post_request(uri) if @method == "POST"
            raise("Unknown request method %s" % @method)
          end

          def choria
            @_choria ||= Util::Choria.new(false)
          end

          def http(uri)
            http = choria.https({:target => uri.host, :port => uri.port}, false)

            if verify_ssl
              http.verify_mode = OpenSSL::SSL::VERIFY_PEER
            else
              http.verify_mode = OpenSSL::SSL::VERIFY_NONE
            end

            http.use_ssl = false if uri.scheme == "http"

            http
          end

          def to_execution_result(results)
            result = {
              "value" => results[2].first,
              "error" => {
                "msg" => results[1]
              }
            }

            result.delete("error") if results[0]

            {create_uri.host => result}
          end

          def run
            uri = create_uri
            resp = http(uri).request(http_request(uri))

            Log.debug("%s request to %s returned code %s with body: %s" % [@method, uri.to_s, resp.code, resp.body])

            if ["200", "201"].include?(resp.code)
              [true, "Successfully sent %s request to webhook %s with id %s" % [@method, @uri, @request_id], [resp.body]]
            else
              [false, "Failed to send %s request to webhook %s with id %s: %s: %s" % [@method, @uri, @request_id, resp.code, resp.body], [resp.body]]
            end
          rescue
            msg = "Could not send %s to webhook %s: %s: %s" % [@method, @uri, $!.class, $!.to_s]
            Log.debug(msg)
            Log.debug($!.backtrace.join("\t\n"))

            [false, msg, []]
          end
        end
      end
    end
  end
end

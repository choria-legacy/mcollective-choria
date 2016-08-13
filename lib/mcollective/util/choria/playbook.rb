require_relative "playbook/metadata"
require_relative "playbook/inputs"
require_relative "playbook/tasks"
require_relative "playbook/nodes"
require_relative "playbook/hooks"
require_relative "playbook/uses"
require_relative "playbook/rpc"

require "semantic_puppet"

module MCollective
  module Util
    class Choria
      class Playbook
        LOG_LEVELS = ["debug", "info", "warn", "error"]
        HOOKS = ["pre_task", "post_task", "on_fail", "on_success", "pre_book", "post_book"]

        class TemplateInterprolationError < StandardError;end
        class DiscoveryValidationError < StandardError;end
        class DependencyError < StandardError;end
        class RPCError < StandardError;end
        class CommsError < StandardError;end
        class TaskError < StandardError;end

        attr_reader :run_as, :loglevel
        attr_reader :metadata, :inputs, :tasks, :hooks, :nodes, :uses

        def initialize
          Applications.load_config

          @run_as = "playbook"
          @loglevel = "info"

          @metadata = Metadata.new(self)
          @inputs = Inputs.new(self)
          @tasks = Tasks.new(self)
          @hooks = Hooks.new(self)
          @nodes = Nodes.new(self)
          @uses = Uses.new(self)
        end

        def run!
          uses.verify_local!
          nodes.test_connectivity!
          nodes.validate_needs!
          tasks.run!
        end

        def input_values_from_hash(hash)
          inputs.values_from_hash(hash)
        end

        def info(msg)
          Log.warn(msg)
        end

        def warn(msg)
          Log.warn(msg)
        end

        def debug(msg)
          Log.warn(msg)
        end

        def devlog(msg)
          Log.warn(msg)
        end

        def template_resolver(dataset, item)
          devlog("Resolving '%s' in dataset '%s'" % [item, dataset])

          case dataset
          when "inputs"
            val = inputs.input_value(item)
            raise(TemplateInterprolationError, "Input %s is not set" % item) if val == :unset
            val
          when "nodes"
            nodes.discovered_nodes(item)
          when "state"
            metadata.value(item)
          else
            raise(TemplateInterprolationError, "Unknown data set %s referenced in a template" % dataset)
          end
        end

        def t_array(array)
          array.map do |item|
            t(item)
          end
        end

        def t_hash(hash)
          hash = hash.dup

          hash.keys.each do |item|
            hash[item] = t(hash[item])
          end

          hash
        end

        def t_string(string)
          pattern = '\${{{\s*(?<set>inputs|nodes|state)\.(?<item>\w+?)\s*}}}'
          whole_string = /^#{pattern}$/
          sub_string = /#{pattern}/

          if match = string.match(whole_string)
            begin
              template_resolver(match[:set], match[:item])
            rescue
              raise(TemplateInterprolationError, "Failed to interprolate %s.%s: %s" % [match[:set], match[:item], $!.to_s])
            end
          else
            string.gsub(sub_string) do |match|
              t(match)
            end
          end
        end

        def t(data)
          if data.is_a?(String)
            t_string(data)
          elsif data.is_a?(Hash)
            t_hash(data)
          elsif data.is_a?(Array)
            t_array(data)
          else
            data
          end
        end

        def from_source(playbook)
          metadata.from_source(
            "name" => playbook["name"],
            "version" => playbook["version"],
            "author" => playbook["author"],
            "description" => playbook["description"],
            "tags" => playbook["tags"]
          )

          self.loglevel = playbook["loglevel"]
          self.run_as = playbook["run_as"]

          tasks.from_source(playbook["tasks"])
          tasks.on_fail = playbook["on_fail"]

          uses.from_source(playbook["uses"])
          inputs.from_source(playbook["inputs"])
          nodes.from_source(playbook["nodes"])
          hooks.from_source(playbook["hooks"])
        end

        def rpc_client(agent)
          RPC.new(agent.to_s, self)
        end

        def loglevel=(level)
          raise("Invalid loglevel %s" % level) unless LOG_LEVELS.include?(level)
          @loglevel = level
        end

        def run_as=(user)
          raise("Invalid username %s" % user) unless user =~ /^[a-zA-Z]+$/

          @run_as = user
        end
      end
    end
  end
end

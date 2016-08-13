module MCollective
  module Util
    class Choria
      class Playbook
        class Uses
          attr_reader :uses, :playbook

          def initialize(playbook)
            @uses = []
            @versions = {}
            @playbook = playbook
          end

          def local_version(agent)
            ddl = DDL.new(agent)
            ddl.meta[:version]
          rescue
            playbook.debug("Failed to load DDL for %s: %s: %s" % [agent, $!.class, $!.to_s])
            nil
          end

          def verify_local!
            @uses.each do |dependency|
              agent = dependency["agent"]
              expected = desired(agent)
              local = local_version(agent)

              if local
                if covers?(agent, local)
                  playbook.debug("Local agent %s version %s satisfies %s" % [agent, local, expected])
                  next
                else
                  raise(DependencyError, "Local node %s version %s does not satisfy %s" % [agent, local, expected])
                end
              else
                raise(DependencyError, "Local node does not have %s agent" % agent)
              end
            end
          end

          def desired(item)
            @versions[item].to_s
          end

          def covers?(item, version)
            # mco didnt enforce semver
            if version =~ /^\d+\.\d+$/
              version = "%s.0" % version
            end

            s_version = SemanticPuppet::Version.parse(version)

            @versions[item].cover?(s_version)
          end

          def from_source(uses)
            @uses = uses

            @uses.each do |item|
              @versions[item["agent"]] = SemanticPuppet::VersionRange.parse(item["version"])
            end
          end
        end
      end
    end
  end
end

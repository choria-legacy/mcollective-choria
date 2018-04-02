require "puppet"
require "puppet_pal"
require "tmpdir"

module MCollective
  module Util
    class BoltSupport
      class PlanRunner
        def self.init_puppet
          TaskResults.include_iterable
          Puppet::Util::Log.newdestination(:console)
        end

        init_puppet

        attr_reader :modulepath

        # @param plan [String] the name of the plan to use
        # @param tmpdir [String] the path to an already existing temporary directory
        # @param modulepath [String] a : seperated list of locations to look for modules
        # @param loglevel [debug, info, warn, err]
        def initialize(plan, tmpdir, modulepath, loglevel)
          @plan = plan
          @loglevel = loglevel
          @modulepath = modulepath.split(":")
          @tmpdir = tmpdir

          raise("A temporary directory could not be created") unless @tmpdir
          raise("A temporary directory could not be created") unless File.directory?(@tmpdir)

          Puppet[:log_level] = @loglevel
        end

        # Determines if the requested plan exist
        #
        # @return [Boolean]
        def exist?
          with_script_compiler do |compiler|
            return !!compiler.plan_signature(@plan)
          end
        end

        # Initialize Puppet to use the configured tmp dir
        def puppet_cli_options
          Puppet::Settings::REQUIRED_APP_SETTINGS.map do |setting|
            "--%s %s" % [setting, @tmpdir]
          end
        end

        # Retrieves the signature of a plan - its parameters and types
        #
        # NOTE: at present it's not possible to extract description or default values
        #
        # @return [Hash]
        def plan_signature
          with_script_compiler do |compiler|
            sig = compiler.plan_signature(@plan)

            raise("Cannot find plan %s in %s" % [@plan, @modulepath.join(":")]) unless sig

            sig.params_type.elements.map do |elem|
              [elem.name, {
                "type" => elem.value_type.to_s,
                "required" => !elem.key_type.is_a?(Puppet::Pops::Types::POptionalType)
              }]
            end
          end
        end

        # Yields a PAL script compiler in the temporary environment
        def with_script_compiler
          in_environment do |env|
            env.with_script_compiler do |compiler|
              yield(compiler)
            end
          end
        end

        # Facts to use in the environment
        def facts
          {
            "choria" => {
              "playbook" => @plan
            }
          }
        end

        # Sets up a temporary environment
        def in_environment
          Puppet.initialize_settings(puppet_cli_options) unless Puppet.settings.global_defaults_initialized?

          Puppet::Pal.in_tmp_environment("choria", :modulepath => @modulepath, :facts => facts) do |env|
            yield(env)
          end
        end

        # Converts a Puppet type into something mcollective understands
        #
        # This is inevitably hacky by its nature, there is no way for me to
        # parse the types.  PAL might get some helpers for this but till then
        # this is going to have to be best efforts.
        #
        # When there is a too complex situation users can always put in --input
        # and some JSON to work around it until something better comes around
        #
        # @param type [String] a puppet type
        # @return [Class, Boolean] The data type, if its an array input or not
        def puppet_type_to_ruby(type)
          array = false

          type = $1 if type =~ /Optional\[(.+)/

          if type =~ /Array\[(.+)/
            type = $1
            array = true
          end

          return [Numeric, array] if type =~ /Integer/
          return [Numeric, array] if type =~ /Float/
          return [Hash, array] if type =~ /Hash/
          return [:boolean, array] if type =~ /Boolean/

          [String, array]
        end

        def run!(params)
          with_script_compiler do |compiler|
            compiler.call_function("choria::run_playbook", @plan, params)
          end
        end

        # Adds the CLI options for an application based on the playbook inputs
        #
        # @param application [MCollective::Application]
        # @param set_required [Boolean]
        def add_cli_options(application, set_required=false)
          sig = plan_signature

          return if sig.nil? || sig.empty?

          sig.each do |name, details|
            type, array = puppet_type_to_ruby(details["type"])

            properties = {
              :description => "Plan input property (%s)" % details["type"],
              :arguments => "--%s %s" % [name.downcase, name.upcase],
              :type => array ? :array : type
            }

            properties[:required] = true if details["required"] && set_required
            properties[:arguments] = "--[no-]%s" % name.downcase if type == :boolean

            application.class.option(name, properties)
          end
        end
      end
    end
  end
end

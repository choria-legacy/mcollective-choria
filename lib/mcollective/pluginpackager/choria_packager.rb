require "yaml"

module MCollective
  module PluginPackager
    class ChoriaPackager
      def initialize(plugin, pluginpath=nil, signature=nil, verbose=false, keep_artifacts=false, module_template=nil)
        @plugin = plugin
        @verbose = verbose
        @keep_artifacts = keep_artifacts
        @module_template = module_template || File.join(File.dirname(__FILE__), "templates", "choria")
      end

      def create_packages
        assert_new_enough_puppet

        begin
          puts("Building AIO module %s" % module_name)

          @tmpdir = Dir.mktmpdir("choria_packager")

          make_module_dirs
          copy_module_files
          render_templates
          run_build
          move_package

          puts("Completed building module for %s" % module_name)
        rescue
          STDERR.puts("Failed to build plugin module: %s: %s" % [$!.class, $!.to_s])
        ensure
          if @keep_artifacts
            puts("Keeping build artifacts")
            puts("Build artifacts saved in %s" % @tmpdir)
          else
            cleanup_tmpdirs
          end
        end
      end

      def version
        if Integer(@plugin.revision) > 1
          "%s-%s" % [@plugin.metadata[:version], @plugin.revision]
        else
          @plugin.metadata[:version]
        end
      end

      def module_name
        "mcollective_%s_%s" % [@plugin.plugintype.downcase, @plugin.metadata[:name].downcase]
      end

      def module_file_name
        "%s-%s-%s.tar.gz" % [@plugin.vendor, module_name, version]
      end

      def dirlist(type)
        @plugin.packagedata[type][:files].map do |file|
          file.gsub(/^\.\//, "") if File.directory?(file)
        end.compact
      rescue
        []
      end

      def filelist(type)
        @plugin.packagedata[type][:files].map do |file|
          file.gsub(/^\.\//, "") unless File.directory?(file)
        end.compact
      rescue
        []
      end

      def hierakey(var)
        "%s::%s" % [module_name, var]
      end

      def module_override_data
        YAML.load_file(".plugin.yaml")
      rescue
        {}
      end

      def plugin_hiera_data
        {
          hierakey(:config_name) => @plugin.metadata[:name].downcase,
          hierakey(:common_files) => filelist(:common),
          hierakey(:common_directories) => dirlist(:common),
          hierakey(:server_files) => filelist(:agent),
          hierakey(:server_directories) => dirlist(:agent),
          hierakey(:client_files) => filelist(:client),
          hierakey(:client_directories) => dirlist(:client)
        }.merge(module_override_data)
      end

      def make_module_dirs
        ["data", "manifests", "files/mcollective"].each do |dir|
          FileUtils.mkdir_p(File.join(@tmpdir, dir))
        end
      end

      def copy_module_files
        @plugin.packagedata.each do |_, data|
          data[:files].each do |file|
            clean_dest_file = file.gsub("./lib/mcollective", "")
            dest_dir = File.expand_path(File.join(@tmpdir, "files", "mcollective", File.dirname(clean_dest_file)))

            FileUtils.mkdir_p(dest_dir) unless File.directory?(dest_dir)
            FileUtils.cp(file, dest_dir) if File.file?(file)
          end
        end
      end

      def render_templates
        templates = Dir.chdir(@module_template) do |_|
          Dir.glob("**/*.erb")
        end

        templates.each do |template|
          infile = File.join(@module_template, template)
          outfile = File.join(@tmpdir, template.gsub(/\.erb$/, ""))
          render_template(infile, outfile)
        end
      end

      def render_template(infile, outfile)
        erb = ERB.new(File.read(infile), nil, "-")
        File.open(outfile, "w") do |f|
          f.puts erb.result(binding)
        end
      rescue
        STDERR.puts("Could not render template %s to %s" % [infile, outfile])
        raise
      end

      def assert_new_enough_puppet
        unless File.executable?("/opt/puppetlabs/bin/puppet")
          raise("Cannot build package. '/opt/puppetlabs/bin/puppet' is not present on the system.")
        end

        s = Shell.new("/opt/puppetlabs/bin/puppet --version")
        s.runcommand
        actual_version = s.stdout.chomp
        required_version = "4.5.1"

        if Util.versioncmp(actual_version, required_version) < 0
          raise("Cannot build package. puppet #{required_version} or greater required.  We have #{actual_version}.")
        end
      end

      def run_build
        PluginPackager.execute_verbosely(@verbose) do
          Dir.chdir(@tmpdir) do
            PluginPackager.safe_system("puppet module build")
          end
        end
      rescue
        STDERR.puts("Build process has failed")
        raise
      end

      def move_package
        package_file = File.join(@tmpdir, "pkg", module_file_name)
        FileUtils.cp(package_file, ".")
      rescue
        STDERR.puts("Could not copy package to working directory")
        raise
      end

      def cleanup_tmpdirs
        FileUtils.rm_r(@tmpdir) if File.directory?(@tmpdir)
      rescue
        STDERR.puts("Could not remove temporary build directory %s" % [@tmpdir])
        raise
      end
    end
  end
end

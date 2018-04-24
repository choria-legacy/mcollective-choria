require "rspec/core/rake_task"
require "yaml"

ENV["CHORIA_RAKE"] = $$.to_s

RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = "--profile" if ENV["TRAVIS"] == "true"
end

task :default => ["spec", "rubocop"]

desc "Run rubycop style checks"
task :rubocop do
  sh("rubocop -f progress -f offenses")
end

namespace :doc do
  desc "Serve YARD documentation on %s:%d" % [ENV.fetch("YARD_BIND", "127.0.0.1"), ENV.fetch("YARD_PORT", "9292")]
  task :serve do
    system("yard server --reload --bind %s --port %d" % [ENV.fetch("YARD_BIND", "127.0.0.1"), ENV.fetch("YARD_PORT", "9292")])
  end

  desc "Generate documentatin into the %s" % ENV.fetch("YARD_OUT", "doc")
  task :yard do
    system("yard doc --markup markdown --output-dir %s" % ENV.fetch("YARD_OUT", "doc"))
  end
end

desc "Set versions and create docs for a release"
task :prep_version do
  abort("Please specify CHORIA_VERSION") unless ENV["CHORIA_VERSION"]

  sh 'sed -i.bak -re \'s/(.+"version": ").+/\1%s",/\' module/choria/metadata.json' % ENV["CHORIA_VERSION"]
  sh 'sed -i.bak -re \'s/(.+"version": ").+/\1%s",/\' module/tasks/metadata.json' % ENV["CHORIA_VERSION"]
  sh 'sed -i.bak -re \'s/mcollective_choria(.+"version_requirement":").+?"/mcollective_choria\1%s"/\' module/tasks/metadata.json' % ENV["CHORIA_VERSION"]
  sh 'sed -i.bak -re \'s/(\s+VERSION\s+=\s+").+/\1%s".freeze/\' ./lib/mcollective/util/choria.rb' % ENV["CHORIA_VERSION"]

  Rake::FileList["lib/**/*.ddl"].each do |file|
    sh 'sed -i.bak -re \'s/(\s+:version\s+=>\s+").+/\1%s",/\' %s' % [ENV["CHORIA_VERSION"], file]
  end

  changelog = File.readlines("CHANGELOG.md")

  File.open("CHANGELOG.md", "w") do |cl|
    changelog.each do |line|
      # rubocop:disable Metrics/LineLength
      cl.puts line

      if line =~ /^\|----------/
        cl.puts "|%s|      |Release %s                                                                                            |" % [Time.now.strftime("%Y/%m/%d"), ENV["CHORIA_VERSION"]]
      end
      # rubocop:enable Metrics/LineLength
    end
  end

  sh "git add CHANGELOG.md lib module"
  sh "git commit -e -m '(misc) Release %s'" % ENV["CHORIA_VERSION"]
  sh "git tag %s" % ENV["CHORIA_VERSION"]
end

desc "Prepare and build the Puppet modules"
task :release do
  Rake::Task[:spec].execute
  Rake::Task[:rubocop].execute
  Rake::Task[:prep_version].execute if ENV["CHORIA_VERSION"]

  ["choria", "tasks"].each do |mod|
    puts "=" * 20
    puts "Building module %s" % mod
    puts "=" * 20
    puts
    sh("mkdir -p module/%s/files/mcollective" % mod)
    sh("rm -rf module/%s/files/mcollective/*" % mod)
    sh("cp .gitignore LICENSE.txt NOTICE module/%s" % mod)
    sh("cp CHANGELOG.md module/choria") if mod == "choria"

    datafile = "module/%s/data/plugin.yaml" % mod

    if File.exist?(datafile)
      plugin = YAML.load(File.read(datafile))

      files = plugin.keys.grep(/_files$/).map {|k| plugin[k]}.flatten
      files.each do |file|
        source = File.join("lib/mcollective", file)
        target = File.join("module", mod, "files/mcollective", file)

        puts "Copying plugin file: %s -> %s" % [source, target]
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(File.join("lib/mcollective", file), File.join("module", mod, "files/mcollective", file))
      end
    end

    Dir.chdir("module/%s" % mod) do
      sh("/usr/bin/env -i PATH=/bin:/usr/bin bash -e /opt/puppetlabs/bin/puppet module build")
    end
  end
end

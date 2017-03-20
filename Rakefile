require "rspec/core/rake_task"

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

  sh 'sed -i.bak -re \'s/(.+"version": ").+/\1%s",/\' module/metadata.json' % ENV["CHORIA_VERSION"]
  sh 'sed -i.bak -re \'s/(\s+VERSION\s+=\s+").+/\1%s".freeze/\' ./lib/mcollective/util/choria.rb' % ENV["CHORIA_VERSION"]

  ["connector/nats.ddl", "discovery/choria.ddl", "agent/choria_util.ddl"].each do |file|
    sh 'sed -i.bak -re \'s/(\s+:version\s+=>\s+").+/\1%s",/\' ./lib/mcollective/%s' % [ENV["CHORIA_VERSION"], file]
  end

  changelog = File.readlines("CHANGELOG.md")

  File.open("CHANGELOG.md", "w") do |cl|
    changelog.each do |line|
      # rubocop:disable Metrics/LineLength
      if line =~ /^\|----------/
        cl.puts line
        cl.puts "|%s|      |Release %s                                                                                           |" % [Time.now.strftime("%Y/%m/%d"), ENV["CHORIA_VERSION"]]
      else
        cl.puts line
      end
      # rubocop:enable Metrics/LineLength
    end
  end

  sh "git add CHANGELOG.md lib module"
  sh "git commit -e -m '(misc) Release %s'" % ENV["CHORIA_VERSION"]
  sh "git tag %s" % ENV["CHORIA_VERSION"]
end

desc "Prepare and build the Puppet module"
task :release do
  Rake::Task[:spec].execute
  Rake::Task[:rubocop].execute
  Rake::Task[:prep_version].execute if ENV["CHORIA_VERSION"]

  sh("mkdir -p module/files/mcollective")
  sh("rm -rf module/files/mcollective/*")
  sh("cp -rv lib/mcollective/* module/files/mcollective/")
  sh("cp CHANGELOG.md COPYING module")
  sh("cp .gitignore module")
  Dir.chdir("module") do
    sh("/opt/puppetlabs/bin/puppet module build")
  end
  sh("rm -rf module/files/mcollective/*")
end

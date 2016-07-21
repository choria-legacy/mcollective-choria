require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

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

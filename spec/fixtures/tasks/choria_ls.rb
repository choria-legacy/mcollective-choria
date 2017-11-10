#!/opt/puppetlabs/bin/puppet/ruby

require "json"

params = JSON.parse(STDIN.read)

puts Dir.entries(params.fetch("directory", "/")).to_json

exit 0

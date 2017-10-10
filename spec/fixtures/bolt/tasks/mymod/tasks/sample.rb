#!/opt/puppetlabs/puppet/bin/ruby

require "json"

params = JSON.parse(STDIN.read)

puts({"value" => params["data"], "key" => params["key"]}).to_json

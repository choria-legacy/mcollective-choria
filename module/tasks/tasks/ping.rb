#!/opt/puppetlabs/puppet/bin/ruby

require "json"

puts({"message" => ENV["PT_message"], "timestamp" => Time.now}.to_json)

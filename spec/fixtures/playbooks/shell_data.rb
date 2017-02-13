#!/usr/bin/env ruby

@action = ENV.fetch("CHORIA_DATA_ACTION", "").downcase
@key = ENV["CHORIA_DATA_KEY"]
@value = ENV["CHORIA_DATA_VALUE"]

abort("Unknown action '%s', valid actions are read, write and delete" % @action) unless ["read", "write", "delete"].include?(@action)
abort("A key is required") unless @key
abort("Writing requires a value") if @action == "write" && !@value

abort("forced failure simulation") if @key == "force_fail"

def read(key)
  STDERR.puts("Reading %s" % [key])

  if File.exist?("/tmp/shell_data_tmp")
    puts File.read("/tmp/shell_data_tmp").chomp
  else
    abort("no value")
  end
end

def write(key)
  STDERR.puts("Writing %s" % [key])

  open("/tmp/shell_data_tmp", "w") {|f| f.puts @value}

  puts @value
end

def delete(key)
  STDERR.puts("Deleting %s" % [key])

  File.unlink("/tmp/shell_data_tmp") if File.exist?("/tmp/shell_data_tmp")

  puts @key
end

send(@action, @key)

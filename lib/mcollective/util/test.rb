require "mcollective"
require "securerandom"

MCollective::Applications.load_config

require_relative "choria"
require_relative "tasks_support"

choria = MCollective::Util::Choria.new(false)
tasks = MCollective::Util::TasksSupport.new(choria, "/tmp/task-cache")

meta = tasks.task_metadata("choria::ls", "production")

pp meta

tasks.download_task(meta)

command = {
  "task" => "choria::ls",
  "input_method" => "stdin",
  "input" => '{"directory": "/tmp"}',
  "files" => meta["files"]
}

requestid = SecureRandom.uuid

pp tasks.run_task_command(requestid, command)

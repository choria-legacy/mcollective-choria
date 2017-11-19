# Execute Choria Playbook Tasks
#
# Any task supported by Choria Playbooks is supported and
# can be used from within a plan, though there is probably
# not much sense in using the Bolt task type as you can just
# use `run_task` or `run_command` directly in the plan.
#
# The options to Playbook tasks like `pre_book`, `on_success`,
# `on_fail` and `post_book` does not make sense within the
# Puppet Plan DSL.
#
# @example disables puppet and wait for all nodes to idle
#
# ~~~ puppet
# choria_task("mcollective",
#   "action" => "puppet.disable",
#   "nodes" => $all_nodes,
#   "properties" => {
#     "message" => "disabled during plan execution ${name}"
#   }
# )
#
# $result = choria_task("mcollective",
#   "action" => "puppet.status",
#   "nodes" => $all_nodes,
#   "assert" => "idling=true",
#   "tries" => 10,
#   "try_sleep" => 30
# )
#
# if $result.ok {
#   choria_task("slack",
#     "token" => $slack_token,
#     "channel" = "#ops",
#     "text" => "All nodes have been disabled and are idling"
#   )
# }
# ~~~
Puppet::Functions.create_function(:choria_task) do
  dispatch :run_task do
    param "String", :type
    param "Hash", :properties
  end

  dispatch :run_mcollective_task do
    param "Hash", :properties
  end

  def run_mcollective_task(properties)
    run_task("mcollective", properties)
  end

  def run_task(type, properties)
    # until bolt is not vendoring puppet
    ["/opt/puppetlabs/mcollective/plugins", "C:/ProgramData/PuppetLabs/mcollective/plugins"].each do |libdir|
      next if $LOAD_PATH.include?(libdir)
      next unless File.directory?(libdir)

      $LOAD_PATH << libdir
    end

    require "mcollective/util/bolt_support"

    results = MCollective::Util::BoltSupport.init_choria.run_task(type, properties)
    Puppet::Pops::Types::ExecutionResult.new(results)
  end
end

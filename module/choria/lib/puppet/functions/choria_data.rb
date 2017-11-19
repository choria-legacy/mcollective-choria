# Read or write data from a Choria Playbook Data Store
#
# Any Data Store supported by Choria Playbooks is supported except the `memory`
# one as there is no shared memory space between these function invocations
#
# @example writing data
#
# ~~~ puppet
# # $data will be "1.2.3" and the value will be stored
# # in the yaml file which would be created if not existing
# $data = choria_data("version", "1.2.3",
#    "type" => "file",
#    "file" => "~/.plan.rc",
#    "format" => "yaml",
#    "create" => true
# )`
# ~~~
#
# @example reading data
#
# ~~~ puppet
# # if ran after the previous example $data will equal "1.2.3"
# $data = choria_data("version",
#    "type" => "file",
#    "file" => "~/.plan.rc",
#    "format" => "yaml"
# )
# ~~
#
# The properties passed to the function is identical to those documents
# in the [Choria Playbook Documentation](https://choria.io/docs/playbooks/data/).
Puppet::Functions.create_function(:choria_data) do
  dispatch :read do
    param "String", :item
    param "Hash", :properties
  end

  dispatch :write do
    param "String", :item
    param "String", :value
    param "Hash", :properties
  end

  def init
    # until bolt is not vendoring puppet
    ["/opt/puppetlabs/mcollective/plugins", "C:/ProgramData/PuppetLabs/mcollective/plugins"].each do |libdir|
      next if $LOAD_PATH.include?(libdir)
      next unless File.directory?(libdir)

      $LOAD_PATH << libdir
    end

    require "mcollective/util/bolt_support"

    MCollective::Util::BoltSupport.init_choria
  end

  def read(item, properties)
    init.data_read(item, properties)
  end

  def write(item, value, properties)
    init.data_write(item, value, properties)
  end
end

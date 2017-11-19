# Discovers nodes using Choria Playbook Node Seets
#
# Any Node Set that Choria Playbooks support can be used
# to discover nodes, test their Choria availability and
# audit their agents
#
# @example discover using mcollective
#
# ~~~ puppet
# # Discovers machines using apache in the UK
# # test their reachability over mcollective and
# # ensure they have the puppet agent is newer than
# # version 1.2.3
# $nodes = choria_discover("mcollective",
#   "classes" => ["apache"],
#   "facts" => ["country=uk"],
#   "test" => true,
#   "uses" => ["puppet" => ">= 1.2.3"]
# )
# ~~~
#
# @example discover using terraform outputs
#
# ~~~ puppet
# $nodes = choria_discover("terraform",
#   "statefile" => "/path/to/terraform.tfstate",
#   "output" => "webservers"
# )
# ~~~
#
# @example perform PQL queries
#
# ~~~ puppet
# $nodes = choria_discover("pql",
#    "query" => "facts { name = 'country' and value = '${country}' }"
# )
# ~~~
#
# @example mcollective discovery shortcut
#
# ~~~ puppet
# # On the assumption that mcollective discovery will be
# # used most there is a shortcut
# $nodes = choria_discover(
#   "classes" => ["apache"],
#   "facts" => ["country=uk"],
#   "test" => true,
#   "uses" => ["puppet" => ">= 1.2.3"]
# )
# ~~~
Puppet::Functions.create_function(:choria_discover) do
  dispatch :mcollective_discover do
    param "Hash", :options
  end

  dispatch :discover do
    param "String", :type
    param "Hash", :options
  end

  def mcollective_discover(options)
    discover("mcollective", options)
  end

  def discover(type, options)
    # until bolt is not vendoring puppet
    ["/opt/puppetlabs/mcollective/plugins", "C:/ProgramData/PuppetLabs/mcollective/plugins"].each do |libdir|
      next if $LOAD_PATH.include?(libdir)
      next unless File.directory?(libdir)

      $LOAD_PATH << libdir
    end

    require "mcollective/util/bolt_support"

    MCollective::Util::BoltSupport.init_choria.discover_nodes(type, options)
  end
end


+++
title = "Application Orchestrator"
toc = true
weight = 250
+++

Choria includes an Open Source Orchestrator compatible with the Puppet Site catalog system that allows you to describe a multi node deployment.

This orchestrator interprets the environment graphs Puppet produces and runs your nodes in the right order.

It uses the standard Puppet agent, best installed with ripienaar/mcollective_agent_puppet.

To use it requires some careful configuration, see the bottom of this page for details of that.

## Example

The Puppet Site catalogs allow you describe a graph of multiple nodes, their dependencies, ordering and exchange information between them.

Here is a sample site with a Lamp stack:

```puppet
site {
  lamp{'app2':
    db_user       => 'user',
    db_password   => 'secret',
    web_instances => 3,
    nodes         => {
      Node['dev1.example.net'] => Lamp::Mysql['app2'],
      Node['dev2.example.net'] => Lamp::Webapp['app2-1'],
      Node['dev3.example.net'] => Lamp::Webapp['app2-2'],
      Node['dev4.example.net'] => Lamp::Webapp['app2-3']
    }
  }

  lamp{'app1':
    db_user       => 'user',
    db_password   => 'secret',
    web_instances => 3,
    nodes         => {
      Node['dev1.example.net'] => Lamp::Mysql['app1'],
      Node['dev2.example.net'] => Lamp::Webapp['app1-1'],
      Node['dev3.example.net'] => Lamp::Webapp['app1-2'],
      Node['dev4.example.net'] => Lamp::Webapp['app1-3']
    }
  }
}
```

You can infer from this that there are node groups and that the _Lamp::Mysql_ needs to be done prior to any _Lamp::Webapp_.  The orchastration part of this involves running Puppet in the desired order.

This tool will ask Puppet for the catalog, and after analysing it for cyclic dependencies, view or deploy it:

```bash
$ mco choria run
Puppet Site Plan for the production Environment

2 applications on 4 managed nodes:

        Lamp[app1]
        Lamp[app2]

Node groups and run order:
   ------------------------------------------------------------------
        dev1.example.net
                Lamp[app1] -> Lamp::Mysql[app1]
                Lamp[app2] -> Lamp::Mysql[app2]

   ------------------------------------------------------------------
        dev2.example.net
                Lamp[app1] -> Lamp::Webapp[app1-1]
                Lamp[app2] -> Lamp::Webapp[app2-1]

        dev3.example.net
                Lamp[app1] -> Lamp::Webapp[app1-2]
                Lamp[app2] -> Lamp::Webapp[app2-2]

        dev4.example.net
                Lamp[app1] -> Lamp::Webapp[app1-3]
                Lamp[app2] -> Lamp::Webapp[app2-3]

Are you sure you wish to run this plan? (y/n) y

        2016-07-14 13:28:38 +0200: Checking if 4 nodes are enabled
        2016-07-14 13:28:38 +0200: Disabling Puppet on 4 nodes: Disabled during orchastration job initiated by rip.mcollective at 2016-07-14 13:28:38 +0200

Running node group 1 with 1 nodes batched 4 a time
        2016-07-14 13:28:38 +0200: Waiting for 1 nodes to become idle
        2016-07-14 13:28:38 +0200: Enabling Puppet on 1 nodes
        2016-07-14 13:28:38 +0200: Running Puppet on 1 nodes
        2016-07-14 13:28:38 +0200: Waiting for 1 nodes to start a run
        2016-07-14 13:28:43 +0200: Waiting for 1 nodes to become idle
        2016-07-14 13:29:03 +0200: Waiting for 1 nodes to become idle
        2016-07-14 13:29:24 +0200: Waiting for 1 nodes to become idle

Succesful run of 1 nodes in group 1 in 61.46 seconds

Running node group 2 with 3 nodes batched 4 a time
        2016-07-14 13:29:39 +0200: Waiting for 3 nodes to become idle
        2016-07-14 13:29:39 +0200: Enabling Puppet on 3 nodes
        2016-07-14 13:29:39 +0200: Running Puppet on 3 nodes
        2016-07-14 13:29:39 +0200: Waiting for 3 nodes to start a run
        2016-07-14 13:29:45 +0200: Waiting for 3 nodes to become idle
        2016-07-14 13:30:05 +0200: Waiting for 3 nodes to become idle
        2016-07-14 13:30:26 +0200: Waiting for 3 nodes to become idle

Succesful run of 3 nodes in group 2 in 61.78 seconds

        2016-07-14 13:30:41 +0200: Enabling Puppet on 4 nodes
```

## Configuration

Setting up involves a few things, the instructions below work with the FOSS stack

 * You should already have security certificates setup for Choria, run _mco choria request_cert_ if not.
 * Your Puppet Server is found by looking in DNS or manual config as per the deployment guide, defaults to _puppet:8140_.

On your PuppetServer use the _puppetlabs/puppet_authorization_ module to add a authorization rule:

```puppet
puppet_authorization::rule { "puppetlabs environment":
  match_request_path   => "/puppet/v3/environment",
  match_request_type   => "path",
  match_request_method => "get",
  allow                => ["*.mcollective"],
  sort_order           => 510,
  path                 => "/etc/puppetlabs/puppetserver/conf.d/auth.conf",
  notify               => Class["puppetserver::config"]
}
```

This gives certificates *.mcollective access to the environment graph, adjust to local taste.

Add in the old /etc/puppetlabs/puppet/auth.conf add an entry:

```bash
path /puppet/v3/environment
method find
allow *
```

In your _/etc/puppetlabs/puppet/puppet.conf_ add:

```ini
[master]
app_management = true
```

Finally you need to have authorization to use the actions needed on the Puppet Agent, you can give yourself these by adding the following data to Hiera if you do not already have AAA rules, in this manner you can allow app runs to just certain environments, machines or whichever nodes you like:

```yaml
mcollective_agent_puppet::policies:
  - action: "allow"
    callers: "puppet=rip.mcollective"
    actions: "disable,enable,last_run_summary,runonce,status"
    facts: "*"
    classes: "*"
```

## Logic Flow

To give you an idea for what these deployments actually do, this is the logic flow they take:

Once it has the site catalog from the Puppet Server it finds the list of all nodes in the site and also groups of them and the order to run in.

  1. Checks if all the nodes are enabled, if any are disabled it cannot continue
  2. Disables all the nodes so no automated or human triggered runs can interfere
  3. Waits for all nodes to become idle, if after a long timeout they don't exit
  4. Iterate the groups finding the nodes per group, loop them possibly in small batches
     1. Enable Puppet on these nodes
     2. Run Puppet
     3. Wait for it to start, exit if they do not idle after a long time
     4. Wait for it to become idle, exit if they do not go idle after a long time
     5. Disable them all
     6. If any of the nodes had failed resources, fail
  5. Enable all the nodes on success, Disable all the nodes on fail since the stack is now inconsistent

There is some improvements to be made, specifically there's a small window between
running the nodes and disabling them again that another run can start, end of the
day though it works out, all the daemons are idle when the status is fetched and
this is definitely for a run started after the one we needed.  So the end out come
is the same

## Status

The basic feature work and it works with the Open Source PuppetServer too, but the feature in Puppet is extremely new and needs some improvement, this tool is going to be only as good as what Puppet provides.

What?
=====

A Orchastrator compatible with the Puppet Site catalog system that allows you to describe
a multi node deployment.

This orchastrator interprets the environment graphs Puppet produces and runs your nodes
in the right order.

To combat issues with concurrent scheduled or manual runs it will disable Puppet on all nodes
at start of the run and enable them right before interacting with them to start runs, this way
it does have some defence against inconsistant run states and reports though it is not 100%
fool proof.

This is super early days and it's no doubt broken still.

It makes the same assumptions of certificates and security as the `ripienaar/mcollective-security-puppet`
model and as such are dependant on it. Additionally it uses the standard Puppet agent, best installed
with `ripienaar/mcollective_agent_puppet`.

Usage
-----

```
% mco choria --help

Orchastrator for Puppet Applications

Usage: mco choria [OPTIONS] [FILTERS] <ACTION>

The ACTION can be one of the following:

   plan  - view the plan for a specific environment
   run   - run a the plan for a specific environment

The environment is chosen using --environment and the concurrent
runs may be limited using --batch.

The batching works a bit different than typical, it will only batch
based on a sorted list of certificate names, this means the batches
will always run in predictable order.

Application Options
        --environment ENVIRONMENT    The environment to run, defaults to production
        --batch SIZE                 Run the nodes in each group in batches of a certain size
    -c, --config FILE                Load configuration from file rather than default
    -v, --verbose                    Be verbose
    -h, --help                       Display this screen

The Marionette Collective 2.8.8
```

Example
-------

Given a site defined like this:

```puppet
site {
  lamp{'app2':
    db_user       => 'user',
    db_password   => 'secret',
    web_instances => 3,
    nodes                    => {
      Node['dev1.devco.net'] => Lamp::Mysql['app2'],
      Node['dev2.devco.net'] => Lamp::Webapp['app2-1'],
      Node['dev3.devco.net'] => Lamp::Webapp['app2-2'],
      Node['dev4.devco.net'] => Lamp::Webapp['app2-3']
    }
  }

  lamp{'app1':
    db_user       => 'user',
    db_password   => 'secret',
    web_instances => 3,
    nodes                    => {
      Node['dev1.devco.net'] => Lamp::Mysql['app1'],
      Node['dev2.devco.net'] => Lamp::Webapp['app1-1'],
      Node['dev3.devco.net'] => Lamp::Webapp['app1-2'],
      Node['dev4.devco.net'] => Lamp::Webapp['app1-3']
    }
  }
}
```

This tool will ask Puppet for the catalog and view or deploy it:


```
[rip@dev3]% mco choria run
Puppet Site Plan for the production Environment

2 applications on 4 managed nodes:

        Lamp[app1]
        Lamp[app2]

Node groups and run order:
   ------------------------------------------------------------------
        dev1.devco.net
                Lamp[app1] -> Lamp::Mysql[app1]
                Lamp[app2] -> Lamp::Mysql[app2]

   ------------------------------------------------------------------
        dev2.devco.net
                Lamp[app1] -> Lamp::Webapp[app1-1]
                Lamp[app2] -> Lamp::Webapp[app2-1]

        dev3.devco.net
                Lamp[app1] -> Lamp::Webapp[app1-2]
                Lamp[app2] -> Lamp::Webapp[app2-2]

        dev4.devco.net
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

Setup
-----

Setting up involves a few things, the instructions below work with the FOSS stack

First you should have the `ripienaar/mcollective-security-puppet` plugin working and
it's certificates etc.

On your PuppetServer use the `puppetlabs/puppet_authorization` module to add a authorization rule:

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

This gives certificates `*.mcollective` access to the environment graph, adjust to local taste.


Add in the old `/etc/puppetlabs/puppet/auth.conf` add an entry:

```
path /puppet/v3/environment
method find
allow *
```

And finally in your `/etc/puppetlabs/puppet/puppet.conf` add:

```
[master]
app_management = true
```

Finally you need to have authorization to use the actions needed on the Puppet Agent,
you can give yourself these by adding the following data to Hiera:

```yaml
mcollective_agent_puppet::policies:
  - action: "allow"
    callers: "puppet=rip.mcollective"
    actions: "disable,enable,last_run_summary,runonce,status"
    facts: "*"
    classes: "*"
```

Logic Flow
----------

Once it has the site catalog from the Puppet Server it finds the list of all nodes in
the site and also groups of them and the order to run in.

  1. Checks if all the nodes are enabled, if any are disabled it cannot continue
  2. Disables all the nodes so no automated or human triggered runs can interfere
  3. Waits for all nodes to become idle, if after a long timeout they don't exit
  4. Iterate the groups finding the nodes per group, loop them possibly in small batches
     * Enable Puppet on these nodes
     * Run Puppet
     * Wait for it to start, exit if they do not idle after a long time
     * Wait for it to become idle, exit if they do not go idle after a long time
     * Disable them all
     * If any of the nodes had failed resources, fail
  5. Enable all the nodes

There is some improvements to be made, specifically there's a small window between
running the nodes and disabling them again that another run can start, end of the
day though it works out, all the daemons are idle when the status is fetched and
this is definitely for a run started after the one we needed.  So the end out come
is the same

Status?
-------

The basic feature work and it works with the Open Source PuppetServer too.

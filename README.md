What?
=====

A Orchastrator compatible with the Puppet Site catalog system that allows you to describe
a multi node deployment.

This orchastrator interprets the environment graphs Puppet produces and runs your nodes
in the right order.

To combat issues with concurrent scheduled or manual runs it will disable Puppet on all nodes
at start of the run and enable them right before interacting with them to start runs, this way
even though it does not support the new Puppet uniquely named last_run_summary.yaml files it
does have some defence against inconsistant run states and reports.

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

Status?
-------

The basic feature work and it works with the Open Source PuppetServer too.

There is some more to do around ensuring that the status reports this tool base it's success
or fail on are actually ones produced by Puppet Runs it started, Puppet now supports a per
run unique report file, but the MCollective Puppet Agent is unaware of this.

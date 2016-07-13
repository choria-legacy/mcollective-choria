What?
=====

A Orchastrator compatible with the Puppet Site catalog system that allows you to describe
a multi node deployment.

This orchastrator interprets the environment graphs Puppet produces and runs your nodes
in the right order.

This is super early days and it's no doubt broken still.

It makes the same assumptions of certificates and security as the `ripienaar/mcollective-security-puppet`
model and as such are dependant on it.

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

        2016-07-13 20:20:34 +0200: Checking if 4 nodes are enabled

Running node group 1 with 1 nodes
        2016-07-13 20:20:34 +0200: Waiting for 1 nodes to become idle
        2016-07-13 20:20:34 +0200: Running Puppet on 1 nodes
        2016-07-13 20:20:34 +0200: Waiting for 1 nodes to start a run
        2016-07-13 20:20:55 +0200: Waiting for 1 nodes to start a run
        2016-07-13 20:21:00 +0200: Waiting for 1 nodes to become idle
        2016-07-13 20:21:20 +0200: Waiting for 1 nodes to become idle
        2016-07-13 20:21:40 +0200: Waiting for 1 nodes to become idle

Succesful run of 1 nodes in group 1 in 81.74 seconds

Running node group 2 with 3 nodes
        2016-07-13 20:21:56 +0200: Waiting for 3 nodes to become idle
        2016-07-13 20:21:56 +0200: Running Puppet on 3 nodes
        2016-07-13 20:21:56 +0200: Waiting for 3 nodes to start a run
        2016-07-13 20:22:17 +0200: Waiting for 3 nodes to start a run
        2016-07-13 20:22:27 +0200: Waiting for 3 nodes to become idle
        2016-07-13 20:22:47 +0200: Waiting for 3 nodes to become idle
        2016-07-13 20:23:08 +0200: Waiting for 3 nodes to become idle

Succesful run of 3 nodes in group 2 in 87.10 seconds
```

Status?
-------

The basic feature work and it works with the Open Source PuppetServer too.

There is some more to do around ensuring that the status reports this tool base it's success
or fail on are actually ones produced by Puppet Runs it started, Puppet now supports a per
run unique report file, but the MCollective Puppet Agent is unaware of this.

Additionally it does not yet support the new model of cached catalogs.


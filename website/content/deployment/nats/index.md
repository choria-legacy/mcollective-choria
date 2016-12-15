+++
title = "NATS Middleware"
weight = 110
toc = true
+++

Choria uses the excellent [NATS.io](https://nats.io/) broker by default.  It's very fast, light weight, has a simple configuration and is easy to monitor.  It's configured to only accept connections from nodes with certificates signed by the Puppet CA.

One NATS server has been shown to be able to host over 2000 MCollective nodes comfortably using 300MB RAM.

## Prerequisites

 * Broker nodes must be managed by Puppet and have certs signed by your CA
 * Brokers must run on systemd capable hosts such as CentOS 7
 * You need to get the [ripienaar-nats](https://forge.puppet.com/ripienaar/nats) module from the Puppet Forge
 * You need to ensure that port `4222` is reachable from all your Puppet nodes on all NATS servers
 * You need to ensure that in a clustered environment port `4223` is reachable by the NATS cluster hosts
 * If you wish to use the _collectd_ integration, port `8222` must be reachable from _localhost_

## Single or multiple nodes

The decision to run multiple nodes is about availability and scale.  As mentioned NATS can easily handle large numbers of nodes on a single broker, if this is your first deployment there is no reason right now to think about a cluster of brokers.  As you'll see configuring a cluster is very easy and easily done later.

If you choose to do 1 only keep it simple and install it on your Puppet Master.  This removes the need to configure DNS (the next section) and gets you going ready to explore the possibilities quickly, you can easily later add servers.

## Single node

If you just want to run a single NATS server I suggest putting this on the same machine as your Puppet Server which would by default be resolvable as _puppet_.  This means you do not need to configure anything in Choria as that's the default it assumes.

```puppet
node "puppet.example.net" {
  class{"nats: }
}
```

## Cluster of NATS Brokers

You can create a cluster of brokers, pick 3 or 5 machines and include the module on them all listing the entire cluster certnames. If you do a cluster you must configure Choria via [DNS or manually](/deployment/nats/).

```puppet
node "nats1.example.net" {
  class{"nats:
    routes_password => "Vrph54FBcIvdM"
    servers => [
      "nats1.example.net",
      "nats2.example.net",
      "nats3.example.net",
      "nats4.example.net",
      "nats5.example.net"
    ],
  }
}
```

## Collectd Integration

If you use the _puppet-collectd_ module you can optionally integrate with that:

```puppet
node "puppet.example.net" {
  class{"nats:
    manage_collectd => true
  }
}
```

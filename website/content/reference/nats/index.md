+++
title = "NATS Connector"
weight = 310
toc = true
+++

A MCollective Connector plugin for the [NATS](https://nats.io/) middleware broker designed to work within a configured Choria setup.

It's goals are to be secure by default while requiring almost no configuration, it only supports TLS and it only supports doing verified TLS connections to the broker. You cannot disable this.

This plugin uses the nats rubygem which unfortunately needs Event Machine. So you might need compilers on your nodes to install that.

## Basic Setup

In your mcollective config files you should enable this plugin:

```ini
connector = nats
```

If you put your NATS server on your Puppet Master and it uses port _4222_ on the hostname _puppet_ then everything will just work.

If not you can add some DNS SRV records:

```bash
_mcollective-server._tcp   IN  SRV 10  0 4222  nats1.example.net.
_mcollective-server._tcp   IN  SRV 11  0 4222  nats2.example.net.
```

If you use SRV records with Puppet it might be better for you to use the Puppet scheme so you can also do:

```bash
_x-puppet-mcollective._tcp     IN  SRV 10  0 4222  nats1.example.net.
_x-puppet-mcollective._tcp     IN  SRV 11  0 4222  nats2.example.net.
```

At present weights are not considered.

You can hard code the server list, see the Configuration Refernece section below.

## Server TLS Setup

When running as root it assumes it's a server and so SSL settings are as per a Puppet Agent.

## Client TLS Setup

When not running as root it will try to use SSL from your home directory and again some assumptions about you running Puppet 4.

Here the certname is based on your username so _uname.mcollective.pem_, you need to create these certs via your Puppet CA:

```bash
$ mco choria request_cert
```

## Example NATS Server configuration

NATS is pretty easy to deploy, this plugin will only communicate over TLS so you need to configure things correctly.  The _ripienaar-nats_ module does this for you, but here's a example NATS config of a 3 node cluster set up with TLS should you wish to do your own:


```
port: 4222
monitor_port: 8222

debug: false
trace: false

tls {
  cert_file: "/etc/puppetlabs/puppet/ssl/certs/dev1.example.net.pem"
  key_file: "/etc/puppetlabs/puppet/ssl/private_keys/dev1.example.net.pem"
  ca_file: "/etc/puppetlabs/puppet/ssl/certs/ca.pem"
  verify: true
  timeout: 2
}

cluster {
  port: 4223
  no_advertise: true

  tls {
    cert_file: "/etc/puppetlabs/puppet/ssl/certs/dev1.example.net.pem"
    key_file: "/etc/puppetlabs/puppet/ssl/private_keys/dev1.example.net.pem"
    ca_file: "/etc/puppetlabs/puppet/ssl/certs/ca.pem"
    verify: true
    timeout: 2
  }

  authorization {
    user: routes
    password: eighieGhohqu
    timeout: 0.75
  }

  routes = [
    nats-route://routes:s3cret@dev2.example.net:4223
    nats-route://routes:s3cret@puppet1.example.net:4223
  ]
}

max_payload: 1048576
max_pending_size: 10485760
max_connections: 65536
```

You can also get this going quickly using Docker for development:

```bash
$ docker run -d -p 4222:4222 -p 4223:4223 \
  -v /path/to/your/gnatsd.conf:/config/gnatsd.conf \
    -v /etc/puppetlabs/puppet/ssl:/etc/puppetlabs/puppet/ssl \
      --name nats nats --config /config/gnatsd.conf -DV
```

## Plugin Configuration Reference

You should only need to change configuration if you do not accept the defaults, this plugin is intended to
just work, so if you have a standard setup that does not just work please let me know so we can see if it
can be catered for.

|Setting                 |Description|Default|
|------------------------|-----------|-------|
|choria.srv_domain       |Override the domain used for SRV lookups                    |default to _facter networking.domain_|
|choria.middleware_hosts |Comma seperated list of servers like _nats1:4222,nats2:4222_|Uses SRV records or _puppet:4222_|
|nats.user               |Username when connecting to nats                            |not used|
|nats.pass               |Password when connecting to nats                            |not used|

You can set *MCOLLECTIVE_NATS_USERNAME* and *MCOLLECTIVE_NATS_PASSWORD* to configure the _nats.user_ and _nats.pass_.

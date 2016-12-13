+++
title = "PuppetDB Discovery"
toc = true
weight = 210
+++

Choria includes a [PuppetDB](https://docs.puppet.com/puppetdb/) based discovery plugin but it's not enabled by default.

This is an advanced PuppetDB plugin that is subcollective aware and supports node, fact, class and agent filters. It uses the new _Puppet PQL_ under the hood and so requires a very recent PuppetDB.

Using it you get a very fast discovery workflow but without the awareness of which nodes are actually up and responding, it's suitable for situations where you have a stable network, or really care to know when known machines are not responding as is common during software deployments. It makes a very comfortable to use default discovery plugin.

## Requirements

Your MCollective _client_ machine needs to be able to communicate with PuppetDB on its SSL port. The client will use the same certificates that was created using _mco choria request_cert_ so you don't need to do anything with the normal Puppet client-tools config, though you might find setting those up helpful.

{{% notice warning %}}
Giving people access to PuppetDB in this manner will allow them to do all kinds of thing with your data as there are no ACL features in PuppetDB, consider carefully who you allow to connect to PuppetDB on any port.
{{% /notice %}}

## Using

In general you can just go about using MCollective as normal after configuring it (see below).  All your usual filters like _-I_, _-C_, _-W_ etc all work as normal.

Your discovery should take a fraction of a second rather than the usual 2 seconds or more and will reflect what PuppetDB thinks it should be out there.

### PQL
There is an advanced feature that lets you construct complex queries using the [PQL language](https://docs.puppet.com/puppetdb/latest/api/query/v4/pql.html) for discovery though.

```bash
$ mco find -I "pql:nodes[certname] { certname ~ '^dev' }"
dev3.example.net
dev1.example.net
dev2.example.net
```

You can construct very complex queries that can match even to the level of specific properties of resources and classes:

```bash
$ mco find -I "pql:inventory[certname] { resources { type = 'User' and title = 'rip' and parameters.ensure = 'present'}}"
```

PQL queries comes in all forms, there are many examples at the Puppet docs. Though you should note that you must ensure you only ever return the certname as in the above example.

If you configure the Puppet Client Tools (see below) you can test these queries on the CLI:

```bash
% puppet query "inventory[certname] { resources { type = 'User' and title = 'rip' and parameters.ensure = 'present'}}"
[
  {
    "certname": "host1.example.net"
  }
]
```

Your queries **MUST** return the data as above - just the certname property.

## Configuring MCollective

You do not have to configure this to be the default discovery method, instead you can use it just when you need or want:

```bash
$ mco puppet status --dm=choria
```

By passing _--dm=choria_ to MCollective commands you enable this discovery method just for the duration of that command.  This is a good way to test the feature before enabling it by default.

You can set this discovery method to be your default by adding the following hiera data:

```yaml
mcollective::client_config:
  default_discovery_method: "choria"
```

By default it will attempt to find PuppetDB on puppet:8081, you can configure this [using DNS or manually](../../deployment/dns/).

## Configuring Puppet (optional)

It's convenient to be able to query PuppetDB using the _puppet query_ command especially if you want to use the custom PQL based discovery, create ~/.puppetlabs/client-tools/puppetdb.conf with:

```json
{
  "puppetdb": {
    "server_urls": "https://puppet:8081",
    "cacert": "/home/rip/.puppetlabs/etc/puppet/ssl/certs/ca.pem",
    "cert": "/home/rip/.puppetlabs/etc/puppet/ssl/certs/rip.mcollective.pem",
    "key": "/home/rip/.puppetlabs/etc/puppet/ssl/private_keys/rip.mcollective.pem"
  }
}
```

And then install the puppet-client-tools package from the Puppet Labs repos.

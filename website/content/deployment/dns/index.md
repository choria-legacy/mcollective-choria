+++
title = "DNS Setup"
weight = 120
toc = true
+++

By default as per Puppet behaviour the Puppet Master, Puppet CA and NATS brokers are all found on the name _puppet_.  If you are doing a single node NATS installation on the Puppet Master called _puppet_ you do not neeed to configure anything and continue to the next page.

When not using _puppet_ you can configure these settings manually but we strongly suggest you use SRV records if at all possible.

## NATS Brokers

You can configure where your NATS brokers live using these SRV records:

```bash
_x-puppet-mcollective._tcp   IN  SRV 10  0 4222  nats1.example.net.
_x-puppet-mcollective._tcp   IN  SRV 11  0 4222  nats2.example.net.
_x-puppet-mcollective._tcp   IN  SRV 12  0 4222  nats3.example.net.
```

This means you have 3 of them and they all listen on port _4222_.

## Puppet and Puppet CA

If your Puppet CA, PuppetDB and Puppet Server are all on the same host, you can configure that all with a single SRV record that is compatible with Puppet SRV setup.

```bash
_x-puppet._tcp               IN  SRV 10  0 8140  puppet1.example.net.
```

But if you wish to split the CA and DB from the master add these:

```bash
_x-puppet-ca._tcp            IN  SRV 10  0 8140  puppetca1.example.net.
_x-puppet-db._tcp            IN  SRV 10  0 8081  puppetdb1.example.net.
```

## Custom Domain

By default these SRV records will be looked for in your machines _domain_ fact, but you can customize this by creating data in your _Hiera_:

```yaml
mcollective_choria::config:
  srv_domain: "prod.example.net"
```


## Manual Config

If you have to you can configure these locations manually by creating _Hiera_ data:

```yaml
mcollective_choria::config:
  puppetserver_host: "puppet1.example.net"
  puppetserver_port: 8140
  puppetca_host: "ca1.example.net"
  puppetca_port: 8140
  puppetdb_host: "pdb1.example.net"
  puppetdb_port: 8081
  middleware_hosts:
    - "nats1.example.net:4222"
    - "nats2.example.net:4222"
    - "nats3.example.net:4222"
```

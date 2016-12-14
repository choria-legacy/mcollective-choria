+++
title = "Requirements"
weight = 105
toc = true
+++

For MCollective to function we need a few infrastructure components, this guide takes you through setting up all of these:

  * Set up a middleware broker using [NATS.io](https://nats.io/)
  * Configure server locations using DNS or manually if not using defaults
  * Configure MCollective
  * Create your first user

## Requirements

There are very few requirements, a typical up to date Puppet installation following official guidelines will do:

### Required

  * You must use Puppet 4 deployed using the Puppet Inc AIO packages - the one called _puppet-agent_.
  * You must be using a Puppet Master based setup, typically using _puppetserver_.
  * Your mcollective _server.cfg_ and _client.cfg_ should be Factory Default
  * Your SSL certificates should be in the default locations.
  * You need to run middleware, Choria works best with NATS and provides a module to install that for you.
  * Your certnames must match your FQDNs - the default.
  * You need the [ripienaar-mcollective](https://forge.puppet.com/ripienaar/mcollective) and [ripienaar-nats](https://forge.puppet.com/ripienaar/nats) modules.

### Optional

  * An optional PuppetDB integration exist to use PuppetDB as the source of truth.  This requires PuppetDB and extra configuration.
  * Puppet Applications are supported and deployment can be done using Choria, it requires specific setup of your _puppetserver_.

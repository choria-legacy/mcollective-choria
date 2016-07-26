# mcollective_choria

#### Table of Contents

1. [Overview](#overview)
1. [Usage](#usage)
1. [Configuration](#configuration)

## Overview

A distribution of plugins for MCollective designed to give a very smooth and streamlined experience in getting started when using the Puppet 4 AIO connected to a Puppet Server.

The main goal is ease of use and setup while remaining secure. It shares a security model with Puppet and reuse certificates made using the PuppetCA everywhere.

Includes:

  * A Security Plugin for AIO Puppet including a tool to make client certificates
  * A Connector using NATS.io
  * A Discovery plugin for PuppetDB
  * An Orchestrator for the Puppet Multi Node Applications
  * Shared configuration of SSL and other properties
  * Support for SRV records for configuration to atain a zero config setup
  * Every component uses strong SSL encryption that cannot be disabled.


## Module Description

## Usage

This module is automatically set up for you when you use the [ripienaar-mcollective](https://forge.puppet.com/ripienaar/mcollective)
module.

## Configuration

This module will be automatically installed by the `ripienaar-mcollective` module, the only optional configuration
you might want to set is to enable PuppetDB for discovery source:

```yaml
mcollective::common_config:
  default_discovery_method: choria
```

You must have compilers on your machine as the NATS connector will need these, if you wish to configure a different
connector you can set that using the `ripienaar-mcollective` module:

```yaml
mcollective::common_config:
  connector: activemq
```

Server and Client configuration can be added via Hiera and managed through tiers in your site Hiera, they
will be merged with any included in this module

```yaml
mcollective_security_puppet::config:
   example: value
```

This will be added to both the `client.cfg` and `server.cfg`, you can likewise configure server and client
specific settings using `mcollective_choria::client_config` and `mcollective_choria::server_config`.

These settings will be added to the `/etc/puppetlabs/mcollective/plugin.d/` directory in individual files.

For a full list of possible configuration settings see the module [wiki documentation](https://github.com/ripienaar/mcollective-choria/wiki).

## Data Reference

  * `mcollective_choria::gem_dependencies` - Deep Merged Hash of gem name and version this module depends on
  * `mcollective_choria::manage_gem_dependencies` - disable managing of gem dependencies
  * `mcollective_choria::package_dependencies` - Deep Merged Hash of package name and version this module depends on
  * `mcollective_choria::manage_package_dependencies` - disable managing of packages dependencies
  * `mcollective_choria::class_dependencies` - Array of classes to include when installing this module
  * `mcollective_choria::package_dependencies` - disable managing of class dependencies
  * `mcollective_choria::config` - Deep Merged Hash of common config items for this module
  * `mcollective_choria::server_config` - Deep Merged Hash of config items specific to managed nodes
  * `mcollective_choria::client_config` - Deep Merged Hash of config items specific to client nodes
  * `mcollective_choria::client` - installs client files when true - defaults to `$mcollective::client`
  * `mcollective_choria::server` - installs server files when true - defaults to `$mcollective::server`
  * `mcollective_choria::ensure` - `present` or `absent`

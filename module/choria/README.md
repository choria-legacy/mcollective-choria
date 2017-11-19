# mcollective_choria

#### Table of Contents

1. [Overview](#overview)
1. [Usage](#usage)
1. [Configuration](#configuration)

## Overview

A distribution of plugins for MCollective designed to create a production ready MCollective install in 30 minutes.

The main goal is ease of use and installation however a number of new end user features are added to MCollective while building on a the PuppetCA for security.

Includes:

  * A flexible Playbook system that can integrate MCollective and Puppet with many other systems
  * A Connector using [NATS.io](https://nats.io)
  * Support for SRV records for configuration to atain a zero config setup
  * Every component uses strong SSL encryption that cannot be disabled.
  * Integration with PuppetDB, PuppetCA, Puppet Bolt, Puppet Tasks and Puppet Plans.

See [choria.io](http://choria.io) for full details

## Module Description

## Usage

A deployment guide can be found at the [Choria Website](http://choria.io)

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

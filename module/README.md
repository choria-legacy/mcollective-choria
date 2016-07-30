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

A deployment guide can be found at the [wiki](https://github.com/ripienaar/mcollective-choria/wiki)

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

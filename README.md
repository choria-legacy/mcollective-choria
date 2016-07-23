Choria Orchestrator
===================

**NOTE:** This is a WIP, once ready it will be released as a module on the forge

A distribution of plugins for MCollective designed to give a very smooth and streamlined experience
in getting started when using the Puppet 4 AIO connected to a Puppet Server.

The main goal is ease of use and setup while remaining secure.  It shares a security model
with Puppet and reuse certificates made using the PuppetCA everywhere.

Includes:

   * A Security Plugin for AIO Puppet including a tool to make client certificates
   * A Connector using [NATS.io](https://nats.io)
   * A Discovery plugin for PuppetDB
   * An Orchestrator for the [Puppet Multi Node Applications](https://docs.puppet.com/pe/latest/app_orchestration_overview.html)
   * Shared configuration of SSL and other properties
   * Support for SRV records for configuration to atain a zero config setup

Every component uses strong SSL encryption that cannot be disabled.

See [the Wiki](https://github.com/ripienaar/mcollective-choria/wiki) for further information

## Contact?

R.I.Pienaar / rip@devco.net / @ripienaar / http://devco.net

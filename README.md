Choria Orchestrator
===================

**NOTE:** This is now in more or less Release Candidate state on Unix, on Windows you cannot use NATS yet, a deployment guide can be found in the wiki

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

See [the Wiki](https://github.com/ripienaar/mcollective-choria/wiki) for a deployment guide.


[![Dependency Status](https://dependencyci.com/github/ripienaar/mcollective-choria/badge)](https://dependencyci.com/github/ripienaar/mcollective-choria) [![Code Climate](https://codeclimate.com/github/ripienaar/mcollective-choria/badges/gpa.svg)](https://codeclimate.com/github/ripienaar/mcollective-choria) [![Build Status](https://travis-ci.org/ripienaar/mcollective-choria.svg?branch=master)](https://travis-ci.org/ripienaar/mcollective-choria) [![Coverage Status](https://coveralls.io/repos/github/ripienaar/mcollective-choria/badge.svg?branch=master)](https://coveralls.io/github/ripienaar/mcollective-choria?branch=master)

## Contact?

R.I.Pienaar / rip@devco.net / [@ripienaar](https://twitter.com/ripienaar) / https://devco.net

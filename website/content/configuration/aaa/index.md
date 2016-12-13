+++
title = "MCollective AAA"
toc = true
weight = 220
+++

MCollective features a full suite of Authentication, Authorization and Auditing capabilities.

  * Authentication - _who_ you are, derived from a certificate
  * Authorization - _what_ you may do on any given node, keyed to your certificate based identity
  * Auditing - _log_ of what you did, showing your certificate based identitty and all requests

Earlier we made a certificate called _rip.mcollective_ which is used to establish your identity as _choria=rip.mcollective_ which will be used throughout in the AAA system.

## Authorization

Choria sets up the popular [Action Policy](https://github.com/puppetlabs/mcollective-actionpolicy-auth) based authorization and does so in a _default deny_ mode which means by default, no-one can make any requests.

Some plugins may elect to ship authorization rules that allow certain read only actions by default - like the _mco puppet status_ command, but you can change or override all of this.

### Site Policies

You can allow your own users only certain access, previously when configuring your first user we did this already via _Hiera_:

```yaml
mcollective::site_policies:
  - action: "allow"
    callers: "choria=rip.mcollective"
    actions: "*"
    facts: "*"
    classes: "*"
```

You'll note this is an array so you can have many policies, site policies are applied to **ALL AGENTS**.

Per agent policies can be configured as here:

This will allow a specific certificate to only _block_ ip addresses on my firewall but nothing else:

```yaml
mcollective_agent_iptables::policies:
  - action: "allow"
    callers: "choria=typhon.mcollective"
    actions: "block"
    facts: "*"
    classes: "*"
```

For full details see the [Action Policy](https://github.com/puppetlabs/mcollective-actionpolicy-auth) docs.

### Per plugin default override

As mentioned by default all actions are denied, you can change a specific agent to default allow via hiera:

```yaml
mcollective_agent_puppet::policy_default: allow
```

### Site wide default policy

By default all actions are denied, while it's not recommended to change this to allow you can do this if desired - like in a Lab environment, via _Hiera_:

```yaml
mcollective::policy_default: allow
```

## Authentication
### Custom certificate names

Authentication is done via the certname embedded in the certificate, certificates must be signed by the Puppet CA.

By default the only certificates that will be accepted are those matching the pattern _/\.mcollective$/_, if you have some special needs you can adjust this via _Hiera_:

```yaml
mcollective_choria::config:
  security.certname_whitelist: "bob, jill, /\.mcollective$/"
```

And you can request custom certificate names on the CLI:

```bash
$ mco choria request_cert --certname bob
```

### Revoking access

Public certificates are distributed automatically but will never be removed.  To remove them you have to manually arrange for the files to be deleted from all nodes - perhaps using Puppet - before a new one can be distributed.  These live in */etc/puppetlabs/mcollective/choria_security/public_certs*.

### Privileged certificates

Unless specifically requested you should never use certificates matching the pattern _/\.privileged\.mcollective$/_, this is an advanced feature that is reserved for a future REST server where Authentication is delegated to a trusted piece of software.

## Auditing

Auditing is configured to write to a log file _/var/log/puppetlabs/mcollective-audit.log_ by default, you should set up rotation if desired (not done by the module), it's contents are like:

```bash
[2016-12-13 08:32:34 UTC] reqid=30d706be63e555db8c073ec17a23af44: reqtime=1481617954 caller=choria=rip.mcollective@dev3.example.net agent=rpcutil action=ping data={:process_results=>true}
[2016-12-13 08:32:43 UTC] reqid=e0c60ad2f58d52699e6524039decc257: reqtime=1481617963 caller=choria=rip.mcollective@dev3.example.net agent=puppet action=status data={:process_results=>true}
[2016-12-13 13:15:09 UTC] reqid=1235e001c9b15414b748ab26607e1063: reqtime=1481634909 caller=choria=rip.mcollective@dev3.example.net agent=puppet action=status data={:process_results=>true}
[2016-12-13 13:15:35 UTC] reqid=cf95bc7621ff55a8a197e3f2e394406e: reqtime=1481634935 caller=choria=rip.mcollective@dev3.example.net agent=puppet action=status data={:process_results=>true}
[2016-12-13 13:15:43 UTC] reqid=18192c7f260c5788a33b60ce4f01771c: reqtime=1481634943 caller=choria=rip.mcollective@dev3.example.net agent=puppet action=status data={:process_results=>true}
```

+++
title = "SSL Security"
weight = 320
toc = true
+++

Choria includes a MCollective Security plugin designed to Just Work and be secure by default.

The major goal is that the configuration should be as little as possible work.
It should be as easy to get a very secure MCollective as it is to get the legacy
_psk_ one working.  To that goal there is only 1 setting you have to set to enable
this and yield a secure working collective.

It shares a similar model to the old MCollective SSL security plugin but:

   * There is no shared private key anywhere
   * The plugin has no settings to change for a default secure behaviour.
     It just works
   * Requestor certs are validated against the Puppet CA and only ones signed by
     it can make requests
   * Public key distribution is automatic and does not require configuring
   * Only certificate names matching _/\.mcollective$/_ can be used, this way
     someone cannot just steal any signed cert from any node and make requests.
     This can though optionally be changed with a configuration option.
   * It provides crypto validated callerid in the form _choria=certname_ for use
     in MCollective AAA
   * Special support exist for making mature AAA compatible REST services that
     can make requests on behalf of other callerids

It requires you to have a working Puppet setup with a Master acting as a CA, it
only supports Puppet 4 AIO. Every MCollective node must already be a Puppet node.

## Client / User Setup

Clients need their own certificates, you use Puppet to obtain them, this will only work
with Puppet AIO paths.

A helper exist to do this for you, run it like:

```
$ mco choria request_cert
```

This will fetch the normal auto detected user certificate, you can supply arguments
to change the certname.

They then set _securityprovider = choria_ in their client configuration and it will work.

Only certificates matching _/\.mcollective$/_ will be usable unless you change defaults
which is not recommended.

Certificates matching _/\.privileged\.mcollective$/_ have special meaning and should only
be approved if you use something like the [REST](../../development/rest) features.

## Server Setup

On the server you have to set _securityprovider = choria_, assuming you have a working
Puppet 4 AIO setup. This plugin itself has no options to change any paths to certificates.

Client certificates are cached in _/etc/puppetlabs/mcollective/choria_security/public_certs_,
the directory will be created if it does not exist.  There is no case where the cert
will be overwritten once cached, changing a cert for user entails you having to remove
the cert from the servers.

### Certificate Whitelist

The default behaviour should be safe enough, you know exactly what will be allowed
when you sign a certificate ending in _.mcollective_ but you might want to have a
whitelist of certificates, this can be controlled with the server config file:

```
plugin.choria.security.certname_whitelist = bob , /\.mcollective$/
```

This will match a specific certificate name _bob_ and the default.

## Manual Client Certificate Requests

The manual certificate request process can be seen here in case the helper is not working or you
want to generate them offline and store somewhere.

```
$ puppet certificate generate ${USER}.mcollective --ca-location remote --ca_server ca.example.net
```

Your CA admins will now have a certificate request that they must sign like normal,
once signed you do:

```
$ puppet certificate find ${USER}.mcollective --ca-location remote --ca_server ca.example.net
$ puppet certificate find ca --ca-location remote --ca_server ca.example.net
```

### Special handling of REST servers and other delegators

The security model of this plugin specifically cater for delegated requests while remaining
compatible with the MCollective Authentication, Authorization and Auditing features.

See [REST](../../development/rest) for details about this scenario.

## Message Protocol Details

Developer details of the messaging protocol in [Message Structure](../../development/messages)

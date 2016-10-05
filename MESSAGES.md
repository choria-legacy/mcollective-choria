## Message Protocol Details

Below this is just developer details, you can easily skip this unless you're curious.

MCollective messages are made up of layers of encoded messages, generally something like:

    ( middleware protocol
      ( transport packet that travels over the middleware
          ( security plugin internal representation
            ( mcollective core representation that becomes M::Message
              ( message body, for RPC request M::RPC::Request and M::RPC::Reply )
            )
          )
        )
      )
    )

This is very similar how on the internet REST is within HTTP within TCP within IP and
eventually within transport specific layers like for Ethernet or WAN protocols.

By doing it this way many end points like the `Mcollective::RPC` can cohabit in
the same system (just like HTTP and FTP can on the intenret), security layers can
be swapped out with different ones ie. the `ssl` and `aes` ones and indeed this
one based on `puppet` PKI.

The security system receives or send serialized packets via the middleware layer
which again is a series of plugins - like `activemq` or `rabbitmq` and these have
their own protocols which allow it to swap out the transport between nodes with
different technology.

In most security plugins the 3rd and 4th layers are combined, but this plugin is
proposing a future core format so right now there's a split, so we have:

    ( Stomp, AMQP, NATS etc
      ( JSON encoded mcollective::security::puppet:request:1 or mcollective::security::puppet:reply:1
          ( encoded mcollective:request:3 or mcollective:reply:3
            ( mcollective core as per #to_legacy_request and #to_legacy_reply
              ( message body, for RPC request M::RPC::Request and M::RPC::Reply )
            )
          )
        )
      )
    )

The `mcollective core representation that becomes M::Message` layer will go away
eventually and be replaced wtih `mcollective:request:3` and `mcollective:reply:3`.

### A note on serialization

Right now the MCollective core has unfortunately exposed Ruby Symbols to the wire,
worse they are not a standard or required and in many cases it's up to the users
to use them or strings.  This means standard JSON cannot be used to encode the
core message and a one size fits all translation layer cannot be written.

So the message structures `mcollective:request:3` and `mcollective:reply:3` today
hosts in their `message` property a core MCollective message with potentially
Symbols in it's body.

So we have to use YAML to serialize these messages.  A critical future goal for mc
is to downgrade the RPC system to only support JSON primitives and to change the
internal message structures to use Strings as keys.

At that point the entire payload will use JSON only and no YAML. And one of the
layers above will go away.

### Puppet Security Plugin Request

The following is a request encoded for delivery using the communication plugins, it
will be JSON encoded before sending:

```json
{
  "$schema": "http://json-schema.org/draft-04/schema#",
  "type": "object",
  "properties": {
    "protocol": {
      "type": "string",
      "enum": [
        "mcollective::security::puppet:request:1"
      ]
    },
    "message": {
      "type": "string",
      "description": "YAML encoded mcollective:request:3"
    },
    "signature": {
      "type": "string",
      "description": "SHA256 based signature of the message using the senders private key"
    },
    "pubcert": {
      "type": "string",
      "description": "PEM format X509 certificate of the sender"
    }
  },
  "required": [
    "protocol",
    "message",
    "signature",
    "pubcert"
  ]
}
```

If it's the first time a request is seen from this public cert its verified against
the CA and cached.

The message is deserialized and the caller id extracted, the matching cert is loaded
from disk and used to validate the signature.  If it passes the deserialized `message`
is returned

The format of a deserialized message is:

```ruby
{
  "protocol" => "mcollective:request:3",
  "message" => Object,
  "envelope" => {
    "requestid" => "bde834cd04835b62a2076b720d6e36d2",
    "senderid" => "some.node",
    "callerid" => "cert=rip.mcollective",
    "filter" => {
      "fact" => [],
      "cf_class" => [],
      "agent" => ["rpcutil"],
      "identity" => [],
      "compound" => []},
    },
    "collective" => "mcollective",
    "agent" => "rpcutil",
    "ttl" => 60
    "time" => 1463840020
  }
}
```

At the moment the message is YAML serialized before encoding in the JSON that goes to the
connectors but in future versions of MCollective the core message will become JSON safe and
it will be JSON encoded instead.

Eventually this `mcollective:request:3` will become the core MCollective protocol, for now
this is converted into the current MCollective protocol and goes to become a `MCollective::Message`:

```ruby
{
  :body => request["message"],
  :senderid => request["envelope"]["senderid"],
  :requestid => request["envelope"]["requestid"],
  :filter => request["envelope"]["filter"],
  :collective => request["envelope"]["collective"],
  :agent => request["envelope"]["agent"],
  :callerid => request["envelope"]["callerid"],
  :ttl => request["envelope"]["ttl"],
  :msgtime => request["envelope"]["time"]
}
```

### Puppet Security Plugin Reply

The following is a reply encoded for delivery using the communication plugins, it
will be JSON encoded before sending:

```json
{
  "$schema": "http://json-schema.org/draft-04/schema#",
  "type": "object",
  "properties": {
    "protocol": {
      "type": "string",
      "enum": [
        "mcollective::security::puppet:reply:1"
      ]
    },
    "message": {
      "type": "string",
      "description": "YAML encoded mcollective:reply:3"
    },
    "hash": {
      "type": "string",
      "description": "SHA256 has of the message"
    }
  },
  "required": [
    "protocol",
    "message",
    "hash"
  ]
}
```

The format of the deserialized message is:

```ruby
{
  "protocol" => "mcollective:reply:3",
  "message" => Object,
  "envelope" => {
    "senderid" => "some.node",
    "requestid" => "bde834cd04835b62a2076b720d6e36d2",
    "agent" => "rpcutil",
    "time" => 1463840021
  }
}
```

Eventually this `mcollective:reply:3` will become the core MCollective protocol, for now
this is converted into the current MCollective protocol and goes on to become a `MCollective::Message`:

```ruby
{
  :senderid => reply["envelope"]["senderid"],
  :requestid => reply["envelope"]["requestid"],
  :senderagent => reply["envelope"]["agent"],
  :msgtime => reply["envelope"]["time"],
  :body => reply["message"]
}
```

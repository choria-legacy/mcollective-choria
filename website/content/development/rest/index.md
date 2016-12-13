+++
title = "REST Server Support"
weight = 410
toc = true
+++

In the past several attempts have been made to create REST gateways for MCollective but most of them were not very good.

   * They did not set callerids thus the AAA model was broken
   * They expect REST clients to wait for the duration of the request and so
     consume many resources internal to them and generally are just a bad fit
     for REST
   * MCollective is not pure JSON

The first requires a cooperative Security Plugin, this plugin is one and lets one build a REST gateway that works with the MCollective AAA design.

The Choria security plugin has specific support for building REST services to interact with MCollective.

```text
+---------+                           +-------+                         +---------+
| Client  |                           | REST  |                         | Server  |
+---------+                           +-------+                         +---------+
     |                                    |                                  |
     | Obtain Auth Token                  |                                  |
     |----------------------------------->|                                  |
     |                                    |                                  |
     |                  Stores Auth Token |                                  |
     |<-----------------------------------|                                  |
     |                                    |                                  |
     | MCollective Request with Token     |                                  |
     |----------------------------------->|                                  |
     |                                    |                                  |
     |                                    | /---------------\                |
     |                                    |-| Internal RBAC |                |
     |                                    | \---------------/                |
     |                                    |                                  |
     |                                    |                                  |
     |                                    | signed with privileged user      |
     |                                    | cert sets token based callerid   |
     |                                    |--------------------------------->|
     |                                    |                                  |
     |                          RequestID |                                  |
     |<-----------------------------------|                                  |
     |                                    |                                  | /-----------------------\
     |                                    |                                  |-| AAA based on callerid |
     |                                    |                                  | \-----------------------/
     |                                    |                                  |
     |                                    |                           result |
     |                 /---------------\  |<---------------------------------|
     |                 | Stores results |-|                           result |
     |                 |  in a database | |<---------------------------------|
     |                 \-------------- /  |                           result |
     |                                    |<---------------------------------|
     |                                    |                                  |
     | Request results for RequestID      |                                  |
     |----------------------------------->|                                  |
     |                                    | /------------------\             |
     |                                    |-|Retrieves from DB |             |
     |                                    | \------------------/             |
     |           Result set for RequestID |                                  |
     |<-----------------------------------|                                  |
     |                                    |                                  |
```

Here the REST service has it's own token based authentication - perhaps OAth or similar, and would have an internal username schema for it's users.

It would have a MCollective certificate that's considered a Privileged User certificate and so can set the _callerid_ to any value it likes.  To MCollective the _callerid_ would be _choria=uid_set_by_rest_ where AAA can happen.

This way the REST gateway can do it's own RBAC, caching, security model etc and with the model above the clients do not need to wait - results spool back from a database, can be paged and retrieved at any later date

To set this up the REST service would get it's own SSL certs as any other clients and nodes would need to be specifically configured to trust the REST gateway as a _Privileged User_ capable of setting _callerid_ != _certname_

By default any certificate matching _/\.privileged.mcollective$/_ will be a privileged user but you can specificy a list like:

```
plugin.choria.security.privileged_users = rest_gateway_1.mcollective, rest_gateway_2.mcollective
```

MCollective is still not pure JSON but this might change in the near future.

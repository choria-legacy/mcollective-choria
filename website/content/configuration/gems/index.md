+++
title = "Gem Distribution"
toc = true
weight = 240
+++

Many sites have policies prohibiting their nodes from accessing dependencies via the internet.  Choria allows those to manage their own dependencies and disable the built in Gem management:

You can package the [nats-pure](https://rubygems.org/gems/nats-pure) dependency yourself, perhaps using [fpm](https://fpm.readthedocs.io/en/latest/), and distribute it using your own packages.

You can configure Choria to not install any gem dependencies via _Hiera_:

```yaml
mcollective_choria::manage_gem_dependencies: false
```

You can then configure Choria to install these for you via the system packager, lets say you called the package _aio-nats-pure_, again via _Hiera_:

```yaml
mcollective_choria::package_dependencies:
  "aio-nats-pure": "0.1.2"
```

It will now install this package for you and allow you to manage the version of it, ordering is handled correctly and MCollective will restart appropriately.

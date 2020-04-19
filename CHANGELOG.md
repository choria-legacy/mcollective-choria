|Date      |Issue |Description                                                                                              |
|----------|------|---------------------------------------------------------------------------------------------------------|
|2020/04/19|      |Release 0.17.2                                                                                           |
|2020/01/23|619   |Place the rpcutil DDL in the correct directory                                                           |
|2019/12/05|616   |Correctly extract the playbook name from facts                                                           |
|2019/12/03|613   |Improve remote request signing support                                                                   |
|2019/11/27|611   |Fail gracefully when modulepath is unset                                                                 |
|2019/11/27|      |Release 0.17.1                                                                                           |
|2019/11/27|      |Update `choria-mcorpc-support` dependency                                                                |
|2019/11/26|      |Release 0.17.0                                                                                           |
|2019/11/21|607   |Support using Synadia NATS NGS as a broker for Choria                                                    |
|2019/11/01|591   |Support both Puppet 5 and 6 paths for the task helper                                                    |
|2019/10/28|416   |Detect pure string results from Playbooks and render them correctly                                      |
|2019/10/27|600   |Align playbook log level names with Puppet                                                               |
|2019/09/26|      |Release 0.16.1                                                                                           |
|2019/09/26|      |Use latest mcorpc ruby support gem                                                                       |
|2019/09/20|      |Release 0.16.0                                                                                           |
|2019/08/30|593   |Switch to using JSON format by default                                                                   |
|2019/08/17|593   |Improve puppet db SRV lookup port resolution                                                             |
|2019/06/07|590   |Allow playbook node sets to declare zero discovered hosts is ok with `empty_ok`                          |
|2019/05/27|      |Release 0.15.0                                                                                           |
|2019/05/02|585   |Add support for Choria Autonomous Agents                                                                 |
|2019/03/19|583   |Fix path expansion for token locations with `~` in them                                                  |
|2019/03/04|      |Release 0.14.1                                                                                           |
|2019/03/04|      |Require the latest choria-mcorpc-support gem                                                             |
|2019/03/04|      |Release 0.14.0                                                                                           |
|2019/04/02|578   |Add `-T` to the `federation trace` command                                                               |
|2019/02/12|574   |Improve error messages when a token file cannot be found                                                 |
|2019/01/29|572   |Disable TLS verify when speaking to signers as we are not guaranteed to have client certs                |
|2019/01/24|      |Ensure policy defaults are honored correctly                                                             |
|2019/01/23|      |Release 0.13.1                                                                                           |
|2019/01/23|568   |Include the signer files when installing the module                                                      |
|2019/01/23|      |Release 0.13.0                                                                                           |
|2019/01/03|563   |Support a remote signing service for centralised AAA                                                     |
|2018/12/27|      |Release 0.12.1                                                                                           |
|2018/12/26|560   |Increase `choria_util` timeout to allow for slow facter                                                  |
|2018/12/19|557   |Export the PKI and TLS modes via `choria_util#info`                                                      |
|2018/12/11|550   |Support intermediate certificate chains                                                                  |
|2018/12/11|493   |Support identical settings to the go file security mode allowing non Puppet SSL file paths               |
|2018/12/07|547   |Support disabling PKI and TLS seperately                                                                 |
|2018/12/02|544   |Improve backward compatibility in JSON mode                                                              |
|2018/12/01|      |Release 0.12.0                                                                                           |
|2018/11/27|540   |On AIO Puppet 6 require the `choria-mcorpc-support` gem                                                  |
|2018/11/27|538   |On AIO Puppet 6 always use the JSON serialiser where Choria Server is the default                        |
|2018/11/22|533   |When SSL is disabled do not fail when certificates do not exist                                          |
|2018/09/19|      |Release 0.11.0                                                                                           |
|2018/08/20|528   |Allow custom task wrapper paths to be supplied and support tasks on FreeBSD                              |
|2018/08/16|526   |Correctly report the status of a still-running task after the initial wait is over                       |
|2018/07/26|523   |Avoid infinite reconnection attempts in clients                                                          |
|2018/07/20|      |Release 0.10.0                                                                                           |
|2018/07/11|      |Use `basemodulepath` setting when no module path is given when running playbooks                         |
|2018/07/11|518   |Support CA bundles when doing CA validation                                                              |
|2018/06/16|513   |Set a upper boundary of support of Puppet 6                                                              |
|2018/06/08|511   |Greatly improve performence when consuming messages on large networks by reducing logging                |
|2018/06/06|504   |Rename `_task_id` to `_choria_task_id` and `_task_caller` to `_choria_task_caller` in task executions    |
|2018/06/06|506   |Improve UX consistency wrt Plan vs Playbook                                                              |
|2018/06/06|507   |Randomize NATS connections by default                                                                    |
|2018/05/21|      |Release 0.9.0                                                                                            |
|2018/05/19|498   |Add `_task`, `_task_id` and `_task_caller` to task runtime environments                                  |
|2018/05/16|496   |Update the NATS and Diplomat gems to latest versions                                                     |
|2018/05/15|494   |Improve error messages when attempting to lock a playbook using a data source that does not support locks|
|2018/05/11|460   |Ensure Playbook task results are JSON safe for better interop with Puppet                                |
|2018/05/05|446   |Compensate for inconsistent results from the Puppet Server task API                                      |
|2018/05/04|458   |Enable common RPC options like discovery timeout and method in task run                                  |
|2018/05/03|487   |Support `--batch` and `--batch-sleep` in the task run command                                            |
|2018/05/03|      |Release 0.8.2                                                                                            |
|2018/05/03|484   |Handle tasks without any JSON metadata included - Puppet Server gives inconsistent responses             |
|2018/05/02|      |Release 0.8.1                                                                                            |
|2018/05/02|477   |Improve application descriptions                                                                         |
|2018/05/02|479   |Ensure required arguments can be supplied via JSON data                                                  |
|2018/05/02|478   |Allow Hash inputs to be supplied on the CLI as JSON strings                                              |
|2018/04/25|472   |Ensure tasks with no input arguments can be run                                                          |
|2018/04/25|473   |Improve error messages when a node does not meet the requirements to run tasks                           |
|2018/04/24|      |Release 0.8.0                                                                                            |
|2018/04/23|465   |Include the url schema in the connected server reported by `choria_util#info` action                     |
|2018/04/23|463   |Allow choria discovery method to find machines with numeric fact values                                  |
|2018/04/02|461   |Improve handling of boolean inputs on the CLI in playbooks                                               |
|2018/03/22|      |Correctly report default middleware port in `choria show_config`                                         |
|2018/03/21|430   |Use `https` for the Slack icon                                                                           |
|2018/03/21|448   |Remove the Ruby Federation Broker                                                                        |
|2018/03/21|      |Release 0.7.0                                                                                            |
|2018/03/19|347   |Support running Puppet Tasks                                                                             |
|2018/03/17|434   |Fix dependency handling on Archlinux                                                                     |
|2018/03/17|431   |Update the NATS Client Gem version `0.4.0`                                                               |
|2018/03/08|423   |Remove the `mco federation observe` command                                                              |
|2018/03/05|425   |Default to the users module path when running playbooks                                                  |
|2018/03/05|401   |Remove YAML playbooks                                                                                    |
|2018/03/02|419   |Deprecate the ruby Federation Broker                                                                     |
|2018/02/28|415   |When running playbooks split the modulepath on `:`                                                       |
|2018/02/25|      |Release 0.6.0                                                                                            |
|2018/02/24|383   |Restore deep merging on Ruby Gem dependencies installed by this module                                   |
|2018/02/24|405   |Update NATS gem to 0.3.0                                                                                 |
|2018/02/20|394   |Allow Playbooks to be written using the Puppet Plans DSL                                                 |
|2018/02/16|389   |Remove the `bolt_task` task from playbooks                                                               |
|2018/02/16|376   |Clarify the meaning of version strings from `choria_util#info`                                           |
|2018/02/16|359   |Improve messaging in the `choria_util#info` to differentiate between Ruby and Go versions                |
|2018/02/07|384   |Support stringified booleans and real booleans in choria discovery                                       |
|2017/12/21|      |Release 0.5.0                                                                                            |
|2017/12/20|378   |Arch Linux support                                                                                       |
|2017/10/18|      |Release 0.4.0                                                                                            |
|2017/10/16|348   |Allow Playbooks to be written using the Puppet Plan DSL                                                  |
|2017/10/16|319   |Remove the `mcollective_assert` task                                                                     |
|2017/10/12|351   |Update the systemd module dependencies to support the latest version                                     |
|2017/10/11|      |Release 0.3.1                                                                                            |
|2017/10/11|349   |Update module metadata to install the right files                                                        |
|2017/10/11|      |Release 0.3.0                                                                                            |
|2017/10/10|345   |Support Bolt                                                                                             |
|2017/09/22|341   |Remove the Puppet Application Orchestrator                                                               |
|2017/09/21|      |Release 0.2.0                                                                                            |
|2017/09/21|339   |Promote the `mcollective_assert` `pre_sleep` property to one that applies to all task types              |
|2017/09/20|337   |Fix boolean inputs in playbooks                                                                          |
|2017/09/19|329   |Allow `$schema` in playbook yaml files                                                                   |
|2017/09/19|332   |Support creating data files in the file data store using the `create` property                           |
|2017/09/10|325   |Support saving CLI provided inputs to the data stores automatically                                      |
|2017/09/08|323   |Support disabling TLS programatically, this is not a configurable option                                 |
|2017/09/06|322   |Fix fetching certificates from Ruby Puppet Master                                                        |
|2017/08/19|      |Release 0.1.0                                                                                            |
|2017/08/19|290   |Strip spaces off comma separated host lists to allow for space between hosts                             |
|2017/08/18|314   |Fix fact filters in JSON transport mode                                                                  |
|2017/08/18|307   |When the client is run as root raise an informative error rather than fail silently                      |
|2017/08/16|308   |Remove hard dependency on ajcrowe/supervisord                                                            |
|2017/08/11|310   |Support dot notation for facts when using choria discovery method                                        |
|2017/08/09|192   |Add an `assert` option to the `mcollective` task using JGrep, deprecate `mcollective_assert`             |
|2017/08/02|305   |Handle the case where node inventory data is JSON encoded correctly in playbooks                         |
|2017/08/02|      |Release 0.0.28                                                                                           |
|2017/07/27|301   |Support using supervisord to manage the federation brokers                                               |
|2017/08/02|298   |Update `nats-pure` gem to `0.2.4`                                                                        |
|2017/06/30|296   |Use base64 not hex encoding for reply hashes                                                             |
|2017/06/18|288   |Serialize the innermost body seperately from the container messages                                      |
|2017/06/01|      |Release 0.0.27                                                                                           |
|2017/06/01|267   |Support a pure JSON transport in preparation for a upcoming MCollective release                          |
|2017/06/01|273   |Correctly report paths when doing a federation trace to the host the client runs on                      |
|2017/05/28|274   |Update for version 5 of Hiera and require Puppet >= 4.9.0                                                |
|2017/05/22|271   |Support Choria Discovery Proxy                                                                           |
|2017/05/08|265   |Consult `choria.puppetca_port` configuration when resolving the CA                                       |
|2017/05/04|152   |Add a etcd data store                                                                                    |
|2017/04/19|258   |Show the embedded certname and compare it with the configured certname                                   |
|2017/04/18|      |Release 0.0.26                                                                                           |
|2017/04/18|254   |Improve sanity checks done when validating the overall SSL setup                                         |
|2017/04/12|248   |Allow cert validation to be disabled in webhook                                                          |
|2017/04/12|250   |Accept http code 201 as a valid return code for the webhook playbook task                                |
|2017/03/30|212   |Add batch_sleep_time to mcollective playbook task                                                        |
|2017/03/30|244   |Show correct PuppetDB information in `mco choria show_config`                                            |
|2017/03/30|243   |Show the Choria version in `mco choria show_config`                                                      |
|2017/03/29|      |Release 0.0.25                                                                                           |
|2017/03/27|228   |Support Federations of Collectives                                                                       |
|2017/03/14|229   |Update the NATS gem to 0.2.2                                                                             |
|2017/03/11|213   |Add federation support to the NATS connector                                                             |
|2017/03/08|      |Release 0.0.24                                                                                           |
|2017/03/07|204   |Add a `choria_util` agent that extract running info out of the mcollective daemon                        |
|2017/03/06|173   |Support playbook elapsed time in templates                                                               |
|2017/03/06|201   |Allow server randomization to be configured                                                              |
|2017/02/16|199   |Use the configured *ssl_dir* for storing the public cert cache                                           |
|2017/02/19|186   |Add a Graphite event task                                                                                |
|2017/02/17|      |Release 0.0.23                                                                                           |
|2017/02/14|193   |Improve support for custom CAs by making x509 subject parsing more robust                                |
|2017/02/14|191   |Add the `mco choria show_config` command to inspect active Choria configuration                          |
|2017/02/13|187   |Support *{{ ... }}* as well as *{{{ ... }}}* in templates                                                |
|2017/02/13|177   |Add a shell script based data store                                                                      |
|2017/02/12|      |Release 0.0.22                                                                                           |
|2017/02/11|181   |Add a registration plugin                                                                                |
|2017/02/09|176   |Create the choria public certs in the right directory on windows                                         |
|2017/02/06|174   |Set the mcollective summary as task outcome when its requested                                           |
|2017/01/31|135   |Add a choria logo to the slack task user                                                                 |
|2017/01/29|      |Release 0.0.21                                                                                           |
|2017/01/29|161   |Improve validation for node lists in the mcollective task                                                |
|2017/01/27|165   |Create environment and file data stores                                                                  |
|2017/01/27|166   |Improve validation of the playbook data                                                                  |
|2017/01/26|160   |Fix inputs like :array and a few other types                                                             |
|2017/01/26|163   |Ensure templates are parsed in task descriptions                                                         |
|2017/01/23|      |Release 0.0.20                                                                                           |
|2017/01/23|151   |Add a Consul data source                                                                                 |
|2017/01/21|155   |Allow inputs to be forced to dynamic only inputs                                                         |
|2017/01/21|149   |Support data sources, dynamic inputs, data source read and write tasks                                   |
|2017/01/13|      |Release 0.0.19                                                                                           |
|2017/01/13|147   |Add a color option to the slack task and make it generally prettier                                      |
|2017/01/13|145   |Improve file name handling for reports                                                                   |
|2017/01/13|143   |Always use the identity cert on windows                                                                  |
|2017/01/12|      |Release 0.0.18                                                                                           |
|2017/01/12|      |Release 0.0.17                                                                                           |
|2017/01/12|      |Release 0.0.16                                                                                           |
|2017/01/12|88    |Add playbook reports                                                                                     |
|2017/01/11|101   |Expose previous task status via templates                                                                |
|2017/01/07|129   |Add a choria audit plugin that logs in JSON format                                                       |
|2017/01/04|127   |Allow SRV record support to be disabled                                                                  |
|2017/01/03|      |Release 0.0.15                                                                                           |
|2017/01/03|125   |Adjust dependencies so these modules work with librarian                                                 |
|2016/12/31|      |Release 0.0.14                                                                                           |
|2016/12/31|106   |Update the NATS gem to 0.2.0                                                                             |
|2016/12/29|117   |When both a PuppetDB SRV record and a Puppet one existed results were randomly chosen hosts              |
|2016/12/29|118   |Support UUID and time stamps in templates                                                                |
|2016/12/29|      |Release 0.0.13                                                                                           |
|2016/12/28|113   |Add a terraform node set                                                                                 |
|2016/12/28|96    |Add a webhook task used to GET and POST to other systems                                                 |
|2016/12/27|109   |Add a mcollective_assert task used to check or wait for certain states                                   |
|2016/12/26|102   |Support arguments to commands ran by the shell node set in playbooks                                     |
|2016/12/26|      |Release 0.0.12                                                                                           |
|2016/12/26|104   |Support posting messages to slack as a task step                                                         |
|2016/12/25|95    |Support running shell commands as task steps                                                             |
|2016/12/25|94    |Support YAML files as node set source in Playbooks                                                       |
|2016/12/25|93    |Support shell commands as node set source in Playbooks                                                   |
|2016/12/25|92    |Support PQL queries as node set source in Playbooks                                                      |
|2016/12/25|32    |Add a Playbook system                                                                                    |
|2016/12/16|      |Release 0.0.11                                                                                           |
|2016/12/16|83    |Fix a bug introduced during #55 where Puppet was not correctly initialized                               |
|2016/12/13|      |Release 0.0.10                                                                                           |
|2016/12/11|48    |Use the new Pure Ruby NATS gem and remove EM                                                             |
|2016/11/19|55    |When root consult Puppet configuration to find the SSL dir, make ssl dir configurable                    |
|2016/11/19|68    |Update eventmachine to 1.2.1 and install that by default, improve logging of EM mode and version         |
|2016/11/01|      |Release 0.0.9                                                                                            |
|2016/10/20|61    |Support PQL queries on the CLI for node discovery                                                        |
|2016/10/07|59    |Reqiure missing resolv dependency                                                                        |
|2016/09/12|56    |Filter out deactivated nodes from discovery results                                                      |
|2016/08/22|35    |Simplify facts queries using latest PuppetDB PQL                                                         |
|2016/08/20|52    |Release 0.0.8                                                                                            |
|2016/08/19|49    |Set the connection name                                                                                  |
|2016/08/19|42    |Support NATS gem 0.8.0 and log connected NATS brokers                                                    |
|2016/08/13|      |Release 0.0.7                                                                                            |
|2016/08/13|45    |Fix calling facter on windows                                                                            |
|2016/08/11|      |Release 0.0.6                                                                                            |
|2016/08/10|34    |Correctly declare Apache-2.0 licence                                                                     |
|2016/08/10|37    |Improve errors when a empty site catalog is found                                                        |
|2016/08/01|      |Release 0.0.5                                                                                            |
|2016/08/01|29    |Fix discovery of rpcutil and subclasses                                                                  |
|2016/08/01|      |Release 0.0.4                                                                                            |
|2016/08/01|27    |Install client files only on clients and not everywhere                                                  |
|2016/08/01|27    |Improve discovery of agents in cases where there are client only installs                                |
|2016/07/29|22    |Improve handling of errors from the nodes                                                                |
|2016/07/26|20    |Fix incorrect module data                                                                                |
|2016/07/23|10    |Import mcollective-connector-nats                                                                        |
|2016/07/23|8     |Import mcollective-discovery-puppetdb as `choria` discovery provider                                     |
|2016/07/23|3     |Import mcollective-security-puppet as `choria` security provider                                         |
|2016/07/22|4     |Move orchestrator into a class of its own, add tests                                                     |
|2016/07/22|1     |Detect cyclic catalogs                                                                                   |

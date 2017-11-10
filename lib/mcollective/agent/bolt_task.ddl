metadata :name => "bolt_task",
         :description => "Downloads and runs Puppet Bolt tasks",
         :author => "R.I.Pienaar <rip@devco.net>",
         :license => "Apache-2.0",
         :version => "0.0.1",
         :url => "https://choria.io",
         :timeout => 60

requires :mcollective => "2.11.0"

action "download", :description => "Downloads a Bolt task into a local cache" do
  input :task,
        :prompt      => "Task Name",
        :description => "The name of a task, example apache or apache::reload",
        :type        => :string,
        :validation  => '\A([a-z][a-z0-9_]*)?(::[a-z][a-z0-9_]*)*\Z',
        :optional    => false,
        :maxlength   => 100

  input :environment,
        :prompt      => "Puppet Environment",
        :description => "The environment the task should be fetched from",
        :type        => :string,
        :validation  => '\A[a-z][a-z0-9_]*\z',
        :optional    => false,
        :default     => "production",
        :maxlength   => 100

  input :files,
        :prompt      => "Task Files Specification",
        :description => "The specification of files to download according to v3 api in JSON format",
        :type        => :string,
        :optional    => true,
        :validation  => '\A\[.+\]\z',
        :maxlength   => 2000,
        :default     => "[]"

  output :downloads,
         :description => "The number of files downloaded",
         :display_as  => "Files Downloaded"
end

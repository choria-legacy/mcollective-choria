metadata    :name => "bolt_task",
            :description => "Information about past Bolt Task",
            :author => "R.I.Pienaar <rip@devco.net>",
            :license => "Apache-2.0",
            :version => "0.6.0",
            :url => "https://choria.io",
            :timeout => 1

usage <<-EOU
This data plugin let you extract information about a previously
run Bolt Task for use in discovery and elsewhere.

To run a task on nodes where one previously failed:

   mco tasks run myapp::update -S "bolt_task(ae561842dc7d5a9dae94f766dfb3d4c8).exitcode > 0"
EOU

dataquery :description => "Puppet Bolt Task state" do
    input :query,
          :prompt => "Task ID",
          :description => "The Task ID to retrieve",
          :type => :string,
          :validation  => '^[a-z,0-9]{32}$',
          :maxlength   => 32

    output :known,
           :description => "If this is a known task on this node",
           :display_as => "Known Task",
           :default => false

    output :spool,
           :description => "Where on disk the task status is stored",
           :display_as => "Spool",
           :default => ""

    output :task,
           :description => "The name of the task that was run",
           :display_as => "Task",
           :default => ""

    output :caller,
           :description => "The user who invoked the task",
           :display_as => "Invoked by",
           :default => ""

    output :stdout,
           :description => "The STDOUT output from the task",
           :display_as => "STDOUT",
           :default => ""

    output :stderr,
           :description => "The STDERR output from the task",
           :display_as => "STDERR",
           :default => ""

    output :exitcode,
           :description => "The exitcode from the task",
           :display_as => "Exit Code",
           :default => 127

    output :runtime,
           :description => "How long the task took to run",
           :display_as => "Runtime",
           :default => 0.0

    output :start_time,
           :description => "When the task was started, seconds since 1970 in UTC time",
           :display_as => "Start Time",
           :default => 0

    output :wrapper_spawned,
           :description => "Did the wrapper start successfully",
           :display_as => "Wrapper Spawned",
           :default => false

    output :wrapper_error,
           :description => "Error output from the wrapper command",
           :display_as => "Wrapper Error",
           :default => ""

    output :wrapper_pid,
           :description => "The PID of the wrapper that runs the task",
           :display_as => "Wrapper PID",
           :default => -1

    output :completed,
           :description => "Did the task complete running",
           :display_as => "Completed",
           :default => false
end

metadata :name => "bolt_tasks",
         :description => "Downloads and runs Puppet Tasks",
         :author => "R.I.Pienaar <rip@devco.net>",
         :license => "Apache-2.0",
         :version => "0.17.0",
         :url => "https://choria.io",
         :timeout => 60

requires :mcollective => "2.11.0"

action "download", :description => "Downloads a Puppet Task into a local cache" do
  input :task,
        :prompt      => "Task Name",
        :description => "The name of a task, example apache or apache::reload",
        :type        => :string,
        :validation  => :bolt_task_name,
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
        :optional    => false,
        :validation  => '\A\[.+\]\z',
        :maxlength   => 4000

  output :downloads,
         :description => "The number of files downloaded",
         :display_as  => "Files Downloaded"

  summarize do
    aggregate summary(:downloads)
  end
end

action "run_and_wait", :description => "Runs a Puppet Task that was previously downloaded, wait for it to finish" do
  input :task,
        :prompt      => "Task Name",
        :description => "The name of a task, example apache or apache::reload",
        :type        => :string,
        :validation  => :bolt_task_name,
        :optional    => false,
        :maxlength   => 100

  input :input_method,
        :prompt      => "Input Method",
        :description => "The input method to use",
        :type        => :list,
        :list        => ["powershell", "stdin", "environment", "both"],
        :optional    => true,
        :default     => nil

  input :files,
        :prompt      => "Task Files Specification",
        :description => "The specification of files to download according to v3 api in JSON format",
        :type        => :string,
        :optional    => false,
        :validation  => '\A\[.+\]\z',
        :maxlength   => 4000

  input :input,
        :prompt      => "Task Input",
        :description => "JSON String containing input variables",
        :type        => :string,
        :validation  => '^.+$',
        :optional    => false,
        :default     => "{}",
        :maxlength   => 102400

  output :task_id,
         :description => "The ID the task was created with",
         :display_as  => "Task ID",
         :default     => nil

  output :task,
         :description => "Task name",
         :display_as  => "Task",
         :default     => nil

  output :callerid,
         :description => "User who initiated the task",
         :display_as  => "User",
         :default     => nil

  output :exitcode,
         :description => "Task exit code",
         :display_as  => "Exit Code",
         :default     => 127

  output :stdout,
         :description => "Standard Output from the command",
         :display_as  => "STDOUT",
         :default     => nil

  output :stderr,
         :description => "Standard Error from the command",
         :display_as  => "STDERR",
         :default     => nil

  output :completed,
         :description => "Did the task complete",
         :display_as  => "Completed",
         :default     => false

  output :runtime,
         :description => "Time taken to run the command",
         :display_as  => "Runtime",
         :default     => 0

  output :start_time,
         :description => "When the task was started in UTC time",
         :display_as  => "Start Time"

  summarize do
    aggregate average(:runtime)
    aggregate summary(:task)
    aggregate summary(:callerid)
    aggregate summary(:exitcode)
    aggregate summary(:completed)
    aggregate summary(:task_id)
  end
end

action "run_no_wait", :description => "Runs a Puppet Task that was previously downloaded do not wait for it to finish" do
  input :task,
        :prompt      => "Task Name",
        :description => "The name of a task, example apache or apache::reload",
        :type        => :string,
        :validation  => :bolt_task_name,
        :optional    => false,
        :maxlength   => 100

  input :input_method,
        :prompt      => "Input Method",
        :description => "The input method to use",
        :type        => :list,
        :list        => ["powershell", "stdin", "environment", "both"],
        :optional    => true,
        :default     => nil

  input :files,
        :prompt      => "Task Files Specification",
        :description => "The specification of files to download according to v3 api in JSON format",
        :type        => :string,
        :optional    => false,
        :validation  => '\A\[.+\]\z',
        :maxlength   => 4000

  input :input,
        :prompt      => "Task Input",
        :description => "JSON String containing input variables",
        :type        => :string,
        :validation  => '^.+$',
        :optional    => true,
        :default     => "{}",
        :maxlength   => 102400

  output :task_id,
         :description => "The ID the task was created with",
         :display_as  => "Task ID",
         :default     => nil

  summarize do
    aggregate summary(:task_id)
  end
end

action "task_status", :description => "Request the status of a previously ran task" do
  display :always

  input :task_id,
        :prompt      => "Task ID",
        :description => "The Task ID to retrieve",
        :type        => :string,
        :validation  => '^[a-z,0-9]{32}$',
        :optional    => false,
        :maxlength   => 32

  output :task,
         :description => "Task name",
         :display_as  => "Task",
         :default     => nil

  output :callerid,
         :description => "User who initiated the task",
         :display_as  => "User",
         :default     => nil

  output :exitcode,
         :description => "Task exit code",
         :display_as  => "Exit Code",
         :default     => 127

  output :stdout,
         :description => "Standard Output from the command",
         :display_as  => "STDOUT",
         :default     => nil

  output :stderr,
         :description => "Standard Error from the command",
         :display_as  => "STDERR",
         :default     => nil

  output :completed,
         :description => "Did the task complete",
         :display_as  => "Completed",
         :default     => false

  output :runtime,
         :description => "Time taken to run the command",
         :display_as  => "Runtime",
         :default     => 0

  output :start_time,
         :description => "When the task was started in UTC time",
         :display_as  => "Start Time"

  summarize do
    aggregate average(:runtime)
    aggregate summary(:task)
    aggregate summary(:callerid)
    aggregate summary(:exitcode)
    aggregate summary(:completed)
  end
end

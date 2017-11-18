group :mcollective, :halt_on_fail => true do
  guard :rspec, :cmd => "rspec --fail-fast --format doc" do
    watch(%r{^spec/.+_spec\.rb$})
    watch(%r{^lib/(.+)\.rb$})     { |m| "spec/unit/#{m[1]}_spec.rb" }
    watch("spec/spec_helper.rb")  { "spec" }
  end

  guard :shell do
    watch(%r{^lib|spec/.+\.rb$}) do |m|
      system("rubocop --fail-fast -f progress -f offenses %s" % m) || throw(:task_has_failed)
    end
  end
end

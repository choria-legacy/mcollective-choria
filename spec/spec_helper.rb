require "rubygems"

if ENV["CI"] == "true"
  require "simplecov"
  require "coveralls"

  SimpleCov.formatter = Coveralls::SimpleCov::Formatter
  SimpleCov.start do
    add_filter "spec"
  end
end

require "rspec"
require "mcollective"
require "webmock/rspec"
require "json-schema-rspec"

RSpec.configure do |config|
  config.mock_with(:mocha)
  config.include(JSON::SchemaMatchers)

  config.before :each do
    MCollective::Config.instance.set_config_defaults("")
    MCollective::Config.instance.instance_variable_set("@identity", "rspec_identity")
    MCollective::PluginManager.clear
    MCollective::Connector::Base.stubs(:inherited)
    MCollective::PluginManager.stubs(:[]).with("global_stats").returns(stub)
    MCollective::Log.stubs(:error)
    MCollective::Log.stubs(:warn)
    MCollective::Log.stubs(:info)
    MCollective::Log.stubs(:debug)
  end
end

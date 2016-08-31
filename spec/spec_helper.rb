require "rubygems"

if ENV["CI"] == "true"
  require "coveralls"
  Coveralls.wear!
end

require "rspec"
require "mcollective"
require "rspec/mocks"
require "mocha"
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
    MCollective::Log.stubs(:warn)
    MCollective::Log.stubs(:info)
    MCollective::Log.stubs(:debug)
  end
end

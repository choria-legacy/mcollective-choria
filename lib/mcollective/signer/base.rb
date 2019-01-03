module MCollective
  module Signer
    class Base
      # Register plugins that inherits base
      def self.inherited(klass)
        PluginManager << {:type => "choria_signer_plugin", :class => klass.to_s}
      end

      def initialize
        @config = Config.instance
        @log = Log
      end

      # Signs a secure request
      #
      # Generally for local mode this would just use the users own certificate but if you have a
      # remote signer this might use a token to speak to a remote API, by default Choria supports
      # a standard web service for remote signatures
      #
      # @param secure_request [Hash] a choria:secure:request:1 hash
      # @raise [StandardError] when signing fails
      def sign_secure_request!(secure_request)
        raise(NoMethodError, "undefined method `sign_secure_request!' for %s" % inspect)
      end
    end
  end
end

module MCollective
  module Util
    class IndifferentHash < Hash
      def [](key)
        return super if key?(key)
        return self[key.to_s] if key.is_a?(Symbol)

        super
      end
    end
  end
end

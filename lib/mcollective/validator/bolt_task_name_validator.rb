module MCollective
  module Validator
    class Bolt_task_nameValidator
      def self.validate(name)
        Validator.typecheck(name, :string)

        raise("'%s' is not a valid Bolt Task name" % name) unless name =~ /\A([a-z][a-z0-9_]*)?(::[a-z][a-z0-9_]*)*\Z/
      end
    end
  end
end

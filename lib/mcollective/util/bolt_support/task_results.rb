module MCollective
  module Util
    class BoltSupport
      class TaskResults
        attr_reader :results, :exception
        attr_writer :message

        include Enumerable

        def self.include_iterable
          include(Puppet::Pops::Types::Iterable)
          include(Puppet::Pops::Types::IteratorProducer)
        end

        # Method used by Puppet to create the TaskResults from a array
        #
        # @param results [Array<TaskResult>] hash as prodused by various execution_result method
        # @return [TaskResults]
        def self.from_asserted_hash(results, exception=nil)
          new(results, exception)
        end

        # @param results [Array<TaskResult>]
        def initialize(results, exception=nil)
          @results = results
          @exception = exception
        end

        def to_json(o={})
          @results.to_json(o)
        end

        # Iterate over all results
        #
        # @yield [TaskResult]
        def each
          @results.each {|r| yield r}
        end

        # Set of all the results that are errors regardless of fail_ok
        #
        # @return [TaskResults]
        def error_set
          TaskResults.new(@results.select(&:error))
        end

        # Set of all the results that are ok regardless of fail_ok
        #
        # @return [TaskResults]
        def ok_set
          TaskResults.new(@results.reject(&:error))
        end

        # Determines if all results are ok, considers fail_ok
        #
        # @return [Boolean]
        def ok
          @results.all?(&:ok)
        end
        alias :ok? :ok

        def fail_ok
          @results.all?(&:fail_ok)
        end
        alias :fail_ok? :fail_ok

        def message
          return exception.to_s if exception
          @message
        end

        # List of node names for all results
        #
        # @return [Array<String>]
        def hosts
          @results.map(&:host)
        end

        # First result in the set
        #
        # @return [TaskResult]
        def first
          @results.first
        end

        # Finds a result by name
        #
        # @param host [String] node hostname
        # @return [TaskResult,nil]
        def find(host)
          @results.find {|r| r.host == host}
        end

        # Determines if the resultset is empty
        #
        # @return [Boolean]
        def empty
          @results.empty?
        end
        alias :empty? :empty

        # Determines the count of results in the set
        #
        # @return [Integer]
        def count
          @results.size
        end

        def to_s
          if Object.const_defined?(:Puppet)
            Puppet::Pops::Types::StringConverter.convert(self, "%p")
          else
            super
          end
        end

        def iterator
          if Object.const_defined?(:Puppet) && Puppet.const_defined?(:Pops) && self.class.included_modules.include?(Puppet::Pops::Types::Iterable)
            return Puppet::Pops::Types::Iterable.on(@results, TaskResult)
          end

          raise(NotImplementedError, "iterator requires puppet code to be loaded.")
        end
      end
    end
  end
end

require_relative "base"

require "json"
require "yaml"

module MCollective
  module Util
    class Playbook
      class DataStores
        class FileDataStore < Base
          attr_accessor :file, :format

          def startup_hook
            @file_mutex = Mutex.new
          end

          def from_hash(properties)
            @file = properties["file"]
            @format = properties["format"]

            validate_configuration!

            self
          end

          def validate_configuration!
            raise("No file given to use as data source") unless @file
            raise("No file format given") unless @format
            raise("File format has to be one of 'json' or 'yaml'") unless ["json", "yaml"].include?(@format)

            @file = File.expand_path(@file)

            raise("Cannot find data file %s" % @file) unless File.exist?(@file)
            raise("Cannot read data file %s" % @file) unless File.readable?(@file)
            raise("Cannot write data file %s" % @file) unless File.writable?(@file)

            raise("The data file must contain a Hash or be empty") unless data.is_a?(Hash)
          end

          def data
            @file_mutex.synchronize do
              parse_data
            end
          end

          def parse_data
            return({}) if File.size(@file) == 0

            if @format == "json"
              JSON.parse(File.read(@file))
            elsif @format == "yaml"
              YAML.load(File.read(@file))
            end
          end

          def save_data(raw_data)
            File.open(@file, "w") do |f|
              if @format == "json"
                f.print(JSON.dump(raw_data))
              elsif @format == "yaml"
                f.print(YAML.dump(raw_data))
              end
            end
          end

          def read(key)
            raise("No such key %s" % [key]) unless include?(key)

            data[key]
          end

          def write(key, value)
            @file_mutex.synchronize do
              raw_data = parse_data

              raw_data[key] = value

              save_data(raw_data)
            end

            read(key)
          end

          def delete(key)
            @file_mutex.synchronize do
              raw_data = parse_data

              raw_data.delete(key)

              save_data(raw_data)
            end
          end

          def include?(key)
            data.include?(key)
          end
        end
      end
    end
  end
end

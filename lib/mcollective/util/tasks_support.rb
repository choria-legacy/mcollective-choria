require "digest"
require "uri"
require "tempfile"

module MCollective
  module Util
    class TasksSupport
      attr_reader :cache_dir, :choria

      def initialize(choria, cache_dir=nil)
        @choria = choria
        @cache_dir = cache_dir || @choria.get_option("choria.tasks_cache")
      end

      # Retrieves the list of known tasks in an environment
      #
      # @param environment [String] the environment to query
      # @return [Hash] the v3 task list
      # @raise [StandardError] on http failure
      def tasks(environment)
        resp = http_get("/puppet/v3/tasks?environment=%s" % [environment])

        raise("Failed to retrieve task list: %s: %s" % [$!.class, $!.to_s]) unless resp.code == "200"

        JSON.parse(resp.body)
      end

      # Retrieves the list of known task names
      #
      # @param environment [String] the environment to query
      # @return [Array<String>] list of task names
      # @raise [StandardError] on http failure
      def task_names(environment)
        tasks(environment).map {|t| t["name"]}
      end

      # Parse a task name like module::task into it's 2 pieces
      #
      # @param task [String]
      # @return [Array<String>] 2 part array, first the module name then the task name
      # @raise [StandardError] for invalid task names
      def parse_task(task)
        parts = task.split("::")

        raise("Invalid task name %s" % task) unless parts.size == 2

        parts
      end

      # Determines the cache path for a task file
      #
      # @param file [Hash] a file hash as per the task metadata
      # @return [String] the directory the file would go into
      def task_dir(file)
        File.join(cache_dir, file["sha256"])
      end

      # Determines the full path to cache the task file into
      #
      # @param file [Hash] a file hash as per the task metadata
      # @return [String] the file path to cache into
      def task_file_name(file)
        File.join(task_dir(file), file["filename"])
      end

      # Does a HTTP GET against the Puppet Server
      #
      # @param path [String] the path to get
      # @param headers [Hash] headers to passs
      # @return [Net::HTTPRequest]
      def http_get(path, headers={}, &blk)
        transport = choria.https(choria.puppet_server, true)
        request = choria.http_get(path)

        headers.each do |k, v|
          request[k] = v
        end

        transport.request(request, &blk)
      end

      # Requests a task metadata from Puppet Server
      #
      # @param task [String] a task name like module::task
      # @param environment [String] the puppet environmnet like production
      # @return [Hash] the metadata according to the v3 spec
      # @raise [StandardError] when the request failed
      def task_metadata(task, environment)
        parsed = parse_task(task)
        path = "/puppet/v3/tasks/%s/%s?environment=%s" % [parsed[0], parsed[1], environment]

        resp = http_get(path)

        raise("Failed to request task metadata: %s: %s" % [resp.code, resp.body]) unless resp.code == "200"

        JSON.parse(resp.body)
      end

      # Calculates a hex digest SHA256 for a specific file
      #
      # @param file_path [String] a full path to the file to check
      # @return [String]
      # @raise [StandardError] when the file does not exist
      def file_sha256(file_path)
        Digest::SHA256.file(file_path).hexdigest
      end

      # Determines the file size of a specific file
      #
      # @param file_path [String] a full path to the file to check
      # @return [Integer] bytes
      # @raise [StandardError] when the file does not exist
      def file_size(file_path)
        File.stat(file_path).size
      end

      # Validates a task cache file
      #
      # @param file [Hash] a file hash as per the task metadata
      # @return [Boolean]
      def task_file?(file)
        file_name = task_file_name(file)

        return false unless File.directory?(task_dir(file))
        return false unless File.exist?(file_name)
        return false unless file_size(file_name) == file["size_bytes"]
        return false unless file_sha256(file_name) == file["sha256"]

        true
      end

      # Attempts to download and cache the file
      #
      # @note Does not first check if the cache is ok, unconditionally downloads
      # @see #task_file?
      # @param file [Hash] a file hash as per the task metadata
      # @raise [StandardError] when downloading fails
      def cache_task_file(file)
        path = [file["uri"]["path"], URI.encode_www_form(file["uri"]["params"])].join("?")

        file_name = task_file_name(file)

        Log.debug("Caching task to %s" % file_name)

        http_get(path, "Accept" => "application/octet-stream") do |resp|
          raise("Failed to request task content %s: %s: %s" % [path, resp.code, resp.body]) unless resp.code == "200"

          FileUtils.mkdir_p(task_dir(file), :mode => 0o0750)

          task_file = Tempfile.new("tasks_%s" % file["filename"])
          task_file.binmode

          resp.read_body do |segment|
            task_file.write(segment)
          end

          task_file.close

          FileUtils.chmod(0o0750, task_file.path)
          FileUtils.mv(task_file.path, file_name)
        end
      end

      # Downloads all the files in a task
      #
      # @param task [Hash] the metadata for a task
      # @return [Boolean] indicating download success
      # @raise [StandardError] on download failures
      def download_task(task)
        Log.info("Downloading %d task files" % task["files"].size)

        task["files"].each do |file|
          next if task_file?(file)

          try = 0

          begin
            return false if try == 2

            try += 1

            Log.debug("Downloading task file %s (try %s/2)" % [file["filename"], try])

            cache_task_file(file)
          rescue
            Log.error(msg = "Could not download task file: %s: %s" % [$!.class, $!.to_s])

            sleep 0.1

            retry if try < 2

            raise(msg)
          end
        end

        true
      end
    end
  end
end

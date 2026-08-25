module Versync
  module Adapters
    # Named after the .versync.yml adapter key "bundler", not the Bundler gem —
    # this class does not depend on or require the `bundler` library.
    class Bundler < Base
      GEM_LINE = /^ {4}(\S+) \(([^)]+)\)/.freeze

      def name
        "bundler"
      end

      def available?(project_root)
        File.exist?(gemfile_lock_path(project_root))
      end

      def extract(project_root, options)
        gem_name = options["gem"]
        raise NotFoundError, "bundler adapter requires a 'gem' option" unless gem_name

        path = gemfile_lock_path(project_root)
        raise NotFoundError, "Gemfile.lock not found" unless File.exist?(path)

        version = find_gem_version(path, gem_name)
        raise NotFoundError, "gem '#{gem_name}' not found in Gemfile.lock" unless version

        { value: version, source: "Gemfile.lock" }
      end

      private

      def gemfile_lock_path(project_root)
        File.join(project_root, "Gemfile.lock")
      end

      def find_gem_version(path, gem_name)
        File.foreach(path) do |line|
          match = GEM_LINE.match(line)
          next unless match
          return match[2] if match[1] == gem_name
        end
        nil
      end
    end
  end
end

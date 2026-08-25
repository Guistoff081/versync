module Versync
  module Adapters
    class RubyVersion < Base
      def name
        "ruby_version"
      end

      def available?(project_root)
        File.exist?(ruby_version_path(project_root))
      end

      def extract(project_root, options)
        path = ruby_version_path(project_root)
        raise NotFoundError, ".ruby-version not found" unless File.exist?(path)

        { value: File.read(path).strip, source: ".ruby-version" }
      end

      private

      def ruby_version_path(project_root)
        File.join(project_root, ".ruby-version")
      end
    end
  end
end

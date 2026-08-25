module Versync
  module Adapters
    class NotFoundError < StandardError; end

    class Base
      def name
        raise NotImplementedError
      end

      def available?(project_root)
        raise NotImplementedError
      end

      # options is a Hash of adapter-specific config from .versync.yml.
      # Returns a Hash with :value and :source keys.
      # Raises NotFoundError when the fact cannot be extracted.
      def extract(project_root, options)
        raise NotImplementedError
      end
    end
  end
end

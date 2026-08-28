require "yaml"

module Versync
  module Adapters
    class DockerCompose < Base
      # Compose Spec precedence order — compose.yaml is the modern
      # preferred name; docker-compose.yml is kept for legacy projects.
      CANDIDATE_FILENAMES = %w[compose.yaml compose.yml docker-compose.yaml docker-compose.yml].freeze

      def name
        "docker_compose"
      end

      def available?(project_root)
        !compose_path(project_root).nil?
      end

      def extract(project_root, options)
        service_name = options["service"]
        raise NotFoundError, "docker_compose adapter requires a 'service' option" unless service_name

        path = compose_path(project_root)
        raise NotFoundError, "no compose file found (tried #{CANDIDATE_FILENAMES.join(', ')})" unless path

        compose = YAML.safe_load(File.read(path), aliases: true) || {}
        service = compose.dig("services", service_name)
        raise NotFoundError, "service '#{service_name}' not found in #{File.basename(path)}" unless service

        image = service["image"]
        raise NotFoundError, "service '#{service_name}' has no 'image' key" unless image

        if image.include?("$")
          raise NotFoundError,
                "service '#{service_name}' image '#{image}' uses variable interpolation, which versync cannot resolve"
        end

        tag = extract_tag(image)
        raise NotFoundError, "service '#{service_name}' image '#{image}' has no tag" unless tag

        { value: tag, source: "#{File.basename(path)} (#{service_name})" }
      end

      private

      def compose_path(project_root)
        CANDIDATE_FILENAMES.each do |filename|
          path = File.join(project_root, filename)
          return path if File.exist?(path)
        end
        nil
      end

      # Only treats the last ":" as a tag separator when it appears after the
      # last "/" — otherwise "registry:5000/postgres" would wrongly read
      # "5000/postgres" as the tag. The digest (if any) is stripped first, so
      # "postgres:16@sha256:..." reads the tag as "16" rather than the last
      # colon-separated segment of the digest, and "postgres@sha256:..."
      # (digest-pinned, no tag) correctly reports no tag instead of the
      # digest hash.
      def extract_tag(image)
        reference, = image.split("@", 2)
        last_slash = reference.rindex("/") || -1
        last_colon = reference.rindex(":")
        return nil unless last_colon && last_colon > last_slash

        reference[(last_colon + 1)..]
      end
    end
  end
end

require "test_helper"

module Adapters
  class DockerComposeTest < Minitest::Test
    def setup
      @adapter = Versync::Adapters::DockerCompose.new
      @dir = Dir.mktmpdir
      copy_fixture("docker_compose_project", @dir)
    end

    def teardown
      FileUtils.remove_entry(@dir)
    end

    def test_available_when_compose_file_exists
      assert @adapter.available?(@dir)
    end

    def test_extracts_image_tag_for_service
      assert_equal({ value: "18.1-alpine", source: "compose.yaml (db)" }, @adapter.extract(@dir, { "service" => "db" }))
    end

    def test_raises_not_found_when_service_has_no_tag
      assert_raises(Versync::Adapters::NotFoundError) { @adapter.extract(@dir, { "service" => "no_tag" }) }
    end

    def test_raises_not_found_when_service_has_no_image_key
      assert_raises(Versync::Adapters::NotFoundError) { @adapter.extract(@dir, { "service" => "built" }) }
    end

    def test_raises_not_found_when_service_missing
      assert_raises(Versync::Adapters::NotFoundError) { @adapter.extract(@dir, { "service" => "missing" }) }
    end

    def test_raises_not_found_when_no_service_option
      assert_raises(Versync::Adapters::NotFoundError) { @adapter.extract(@dir, {}) }
    end

    def test_raises_not_found_for_registry_host_port_image_with_no_tag
      assert_raises(Versync::Adapters::NotFoundError) { @adapter.extract(@dir, { "service" => "registry_no_tag" }) }
    end

    def test_extracts_tag_for_registry_host_port_image_with_tag
      result = @adapter.extract(@dir, { "service" => "registry_tag" })
      assert_equal({ value: "18", source: "compose.yaml (registry_tag)" }, result)
    end

    def test_raises_not_found_for_digest_only_image_with_no_tag
      assert_raises(Versync::Adapters::NotFoundError) { @adapter.extract(@dir, { "service" => "digest_only" }) }
    end

    def test_extracts_tag_ignoring_digest_when_both_present
      result = @adapter.extract(@dir, { "service" => "tag_and_digest" })
      assert_equal({ value: "16", source: "compose.yaml (tag_and_digest)" }, result)
    end

    def test_raises_not_found_for_interpolated_tag_with_default
      assert_raises(Versync::Adapters::NotFoundError) { @adapter.extract(@dir, { "service" => "interpolated_with_default" }) }
    end

    def test_raises_not_found_for_interpolated_plain_variable
      assert_raises(Versync::Adapters::NotFoundError) { @adapter.extract(@dir, { "service" => "interpolated_plain" }) }
    end

    def test_falls_back_to_legacy_docker_compose_yml_name
      with_temp_project do |dir|
        copy_fixture("docker_compose_project_legacy_name", dir)
        result = @adapter.extract(dir, { "service" => "db" })
        assert_equal({ value: "16.4", source: "docker-compose.yml (db)" }, result)
      end
    end

    def test_handles_yaml_anchors_and_aliases
      with_temp_project do |dir|
        copy_fixture("docker_compose_project_with_anchors", dir)
        result = @adapter.extract(dir, { "service" => "db" })
        assert_equal({ value: "18.1-alpine", source: "compose.yaml (db)" }, result)
      end
    end
  end
end

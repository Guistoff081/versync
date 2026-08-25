require "test_helper"
require "yaml"

class ConfigurationTest < Minitest::Test
  def test_parses_output_paths_and_fact_configs
    with_temp_project do |dir|
      copy_fixture("config_project", dir)
      config = Versync::Configuration.load(File.join(dir, ".versync.yml"))

      assert_equal "VERSIONS.md", config.markdown_output
      assert_equal "versync.json", config.json_output
      assert_equal(
        [
          Versync::Configuration::FactConfig.new(name: "ruby", adapter: "ruby_version", options: {}),
          Versync::Configuration::FactConfig.new(name: "rails", adapter: "bundler", options: { "gem" => "rails" }),
          Versync::Configuration::FactConfig.new(name: "postgres", adapter: "docker_compose", options: { "service" => "db" })
        ],
        config.fact_configs
      )
    end
  end

  def test_defaults_output_paths_when_absent
    with_temp_project do |dir|
      File.write(File.join(dir, ".versync.yml"), YAML.dump("facts" => {}))
      config = Versync::Configuration.load(File.join(dir, ".versync.yml"))

      assert_equal "VERSIONS.md", config.markdown_output
      assert_equal "versync.json", config.json_output
    end
  end

  def test_raises_enoent_when_file_missing
    with_temp_project do |dir|
      assert_raises(Errno::ENOENT) { Versync::Configuration.load(File.join(dir, ".versync.yml")) }
    end
  end

  def test_raises_invalid_error_when_fact_has_no_adapter
    with_temp_project do |dir|
      File.write(File.join(dir, ".versync.yml"), YAML.dump("facts" => { "ruby" => {} }))
      error = assert_raises(Versync::Configuration::InvalidError) do
        Versync::Configuration.load(File.join(dir, ".versync.yml"))
      end
      assert_includes error.message, "ruby"
    end
  end

  def test_raises_invalid_error_when_fact_body_is_nil
    with_temp_project do |dir|
      File.write(File.join(dir, ".versync.yml"), YAML.dump("facts" => { "ruby" => nil }))
      assert_raises(Versync::Configuration::InvalidError) do
        Versync::Configuration.load(File.join(dir, ".versync.yml"))
      end
    end
  end

  def test_supports_yaml_aliases
    with_temp_project do |dir|
      yaml = <<~YAML
        x-common: &common
          adapter: docker_compose

        facts:
          postgres:
            <<: *common
            service: db
      YAML
      File.write(File.join(dir, ".versync.yml"), yaml)
      config = Versync::Configuration.load(File.join(dir, ".versync.yml"))

      assert_equal "docker_compose", config.fact_configs.first.adapter
    end
  end
end

require "test_helper"
require "stringio"
require "json"
require "yaml"

class CLITest < Minitest::Test
  def run_cli(argv, dir)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Versync::CLI.new(argv, project_root: dir, stdout: stdout, stderr: stderr).run
    [status, stdout.string, stderr.string]
  end

  def test_facts_prints_each_fact_and_returns_0
    with_temp_project do |dir|
      copy_fixture("full_project", dir)
      status, stdout, = run_cli(["facts"], dir)

      assert_equal 0, status
      assert_includes stdout, "ruby: 4.0.6 (.ruby-version)"
      assert_includes stdout, "rails: 8.1.3 (Gemfile.lock)"
    end
  end

  def test_facts_returns_1_when_versync_yml_missing
    with_temp_project do |dir|
      status, _, stderr = run_cli(["facts"], dir)

      assert_equal 1, status
      assert_includes stderr, ".versync.yml not found"
    end
  end

  def test_sync_writes_versions_md_and_versync_json
    with_temp_project do |dir|
      copy_fixture("full_project", dir)
      status, stdout, = run_cli(["sync"], dir)

      assert_equal 0, status
      markdown = File.read(File.join(dir, "VERSIONS.md"))
      json = JSON.parse(File.read(File.join(dir, "versync.json")))

      assert_includes markdown, "| ruby | 4.0.6 | .ruby-version |"
      assert_includes json["facts"], { "name" => "ruby", "value" => "4.0.6", "source" => ".ruby-version" }
      assert_includes stdout, "Synced 4 fact(s)"
    end
  end

  def test_sync_returns_1_when_versync_yml_missing
    with_temp_project do |dir|
      status, _, stderr = run_cli(["sync"], dir)

      assert_equal 1, status
      assert_includes stderr, ".versync.yml not found"
    end
  end

  def test_check_returns_1_when_versync_json_missing
    with_temp_project do |dir|
      copy_fixture("full_project", dir)
      status, _, stderr = run_cli(["check"], dir)

      assert_equal 1, status
      assert_includes stderr, "versync is stale"
    end
  end

  def test_check_returns_0_after_a_sync
    with_temp_project do |dir|
      copy_fixture("full_project", dir)
      run_cli(["sync"], dir)

      status, = run_cli(["check"], dir)
      assert_equal 0, status
    end
  end

  def test_check_returns_1_when_versions_md_deleted_after_sync
    with_temp_project do |dir|
      copy_fixture("full_project", dir)
      run_cli(["sync"], dir)
      File.delete(File.join(dir, "VERSIONS.md"))

      status, _, stderr = run_cli(["check"], dir)
      assert_equal 1, status
      assert_includes stderr, "VERSIONS.md"
    end
  end

  def test_init_writes_versync_yml_from_detected_facts
    with_temp_project do |dir|
      copy_fixture("full_project_without_config", dir)
      status, = run_cli(["init"], dir)

      assert_equal 0, status
      config = YAML.safe_load(File.read(File.join(dir, ".versync.yml")))

      assert_equal %w[ruby rails postgres redis].sort, config["facts"].keys.sort
      assert_equal({ "adapter" => "bundler", "gem" => "rails" }, config["facts"]["rails"])
    end
  end

  def test_init_does_not_overwrite_existing_versync_yml
    with_temp_project do |dir|
      copy_fixture("full_project", dir)
      original = File.read(File.join(dir, ".versync.yml"))

      status, _, stderr = run_cli(["init"], dir)

      assert_equal 1, status
      assert_includes stderr, "already exists"
      assert_equal original, File.read(File.join(dir, ".versync.yml"))
    end
  end

  def test_end_to_end_init_sync_check
    with_temp_project do |dir|
      copy_fixture("full_project_without_config", dir)

      assert_equal 0, run_cli(["init"], dir).first
      assert_equal 0, run_cli(["sync"], dir).first
      assert_equal 0, run_cli(["check"], dir).first

      markdown = File.read(File.join(dir, "VERSIONS.md"))
      assert_includes markdown, "| rails | 8.1.3 | Gemfile.lock |"
    end
  end

  def test_sync_refuses_output_path_that_escapes_project_root
    with_temp_project do |dir|
      copy_fixture("full_project", dir)
      config = File.join(dir, ".versync.yml")
      File.write(config, YAML.load_file(config).merge("output" => { "markdown" => "../evil.md" }).to_yaml)

      status, _, stderr = run_cli(["sync"], dir)

      assert_equal 1, status
      assert_includes stderr, "escapes the project root"
      refute File.exist?(File.join(dir, "..", "evil.md"))
    end
  end

  def test_sync_refuses_identical_markdown_and_json_output_paths
    with_temp_project do |dir|
      copy_fixture("full_project", dir)
      config = File.join(dir, ".versync.yml")
      File.write(config, YAML.load_file(config).merge("output" => { "markdown" => "out.txt", "json" => "out.txt" }).to_yaml)

      status, _, stderr = run_cli(["sync"], dir)

      assert_equal 1, status
      assert_includes stderr, "resolve to the same path"
    end
  end

  def test_sync_refuses_output_path_targeting_a_fact_source
    with_temp_project do |dir|
      copy_fixture("full_project", dir)
      config = File.join(dir, ".versync.yml")
      File.write(config, YAML.load_file(config).merge("output" => { "markdown" => "Gemfile.lock" }).to_yaml)

      status, _, stderr = run_cli(["sync"], dir)

      assert_equal 1, status
      assert_includes stderr, "reads facts from"
      assert_includes File.read(File.join(dir, "Gemfile.lock")), "rails (8.1.3)"
    end
  end

  def test_sync_refuses_output_path_targeting_the_config_file
    with_temp_project do |dir|
      copy_fixture("full_project", dir)
      config = File.join(dir, ".versync.yml")
      File.write(config, YAML.load_file(config).merge("output" => { "json" => ".versync.yml" }).to_yaml)
      configured_content = File.read(config)

      status, _, stderr = run_cli(["sync"], dir)

      assert_equal 1, status
      assert_includes stderr, "reads facts from"
      assert_equal configured_content, File.read(config)
    end
  end

  def test_check_reports_stale_after_gemfile_lock_changes_post_sync
    with_temp_project do |dir|
      copy_fixture("full_project", dir)
      run_cli(["sync"], dir)

      gemfile_lock = File.join(dir, "Gemfile.lock")
      File.write(gemfile_lock, File.read(gemfile_lock).sub("rails (8.1.3)", "rails (8.2.0)"))

      status, _, stderr = run_cli(["check"], dir)

      assert_equal 1, status
      assert_includes stderr, 'rails: documented="8.1.3" actual="8.2.0"'
    end
  end

  def test_unknown_command_returns_1_and_prints_usage
    stdout = StringIO.new
    stderr = StringIO.new
    status = Versync::CLI.new(["bogus"], stdout: stdout, stderr: stderr).run

    assert_equal 1, status
    assert_includes stderr.string, "Usage:"
  end
end

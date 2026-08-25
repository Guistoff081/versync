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

  def test_unknown_command_returns_1_and_prints_usage
    stdout = StringIO.new
    stderr = StringIO.new
    status = Versync::CLI.new(["bogus"], stdout: stdout, stderr: stderr).run

    assert_equal 1, status
    assert_includes stderr.string, "Usage:"
  end
end

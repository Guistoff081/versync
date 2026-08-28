require "test_helper"
require "json"

class DiffCheckerTest < Minitest::Test
  def checker(dir)
    Versync::DiffChecker.new(project_root: dir, json_output: "versync.json", markdown_output: "VERSIONS.md")
  end

  def fresh_markdown(facts)
    Versync::Renderers::Markdown.new(facts: facts, generated_at: Time.now, commit: "whatever").render
  end

  def test_stale_when_json_output_missing
    with_temp_project do |dir|
      facts = [Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version")]
      result = checker(dir).check(facts, rendered_markdown: fresh_markdown(facts))

      assert result.stale?
      assert result.missing_output
    end
  end

  def test_not_stale_when_facts_and_markdown_match
    with_temp_project do |dir|
      facts = [Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version")]
      File.write(File.join(dir, "versync.json"), JSON.generate(
                                                     "generated_at" => "2026-08-25T12:00:00Z", "commit" => "abc123",
                                                     "facts" => [{ "name" => "ruby", "value" => "4.0.6", "source" => ".ruby-version" }]
                                                   ))
      markdown = fresh_markdown(facts)
      File.write(File.join(dir, "VERSIONS.md"), markdown)

      refute checker(dir).check(facts, rendered_markdown: markdown).stale?
    end
  end

  def test_ignores_generated_at_and_commit_differences
    with_temp_project do |dir|
      facts = [Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version")]
      File.write(File.join(dir, "versync.json"), JSON.generate(
                                                     "generated_at" => "2026-08-25T09:00:00Z", "commit" => "old-sha",
                                                     "facts" => [{ "name" => "ruby", "value" => "4.0.6", "source" => ".ruby-version" }]
                                                   ))
      markdown_now = Versync::Renderers::Markdown.new(facts: facts, generated_at: Time.now, commit: "old-sha").render
      markdown_before = Versync::Renderers::Markdown.new(facts: facts, generated_at: Time.now - 3600, commit: "new-sha").render
      File.write(File.join(dir, "VERSIONS.md"), markdown_before)

      refute checker(dir).check(facts, rendered_markdown: markdown_now).stale?
    end
  end

  def test_reports_a_fact_diff_when_a_value_changed
    with_temp_project do |dir|
      File.write(File.join(dir, "versync.json"), JSON.generate(
                                                     "generated_at" => "2026-08-25T12:00:00Z", "commit" => "abc123",
                                                     "facts" => [{ "name" => "rails", "value" => "8.0.2", "source" => "Gemfile.lock" }]
                                                   ))
      current = [Versync::Fact.new(name: "rails", value: "8.1.3", source: "Gemfile.lock")]
      File.write(File.join(dir, "VERSIONS.md"), fresh_markdown(current))

      result = checker(dir).check(current, rendered_markdown: fresh_markdown(current))

      assert result.stale?
      assert_equal [{ name: "rails", before: "8.0.2", after: "8.1.3" }], result.fact_diffs
    end
  end

  def test_stale_when_versions_md_missing
    with_temp_project do |dir|
      facts = [Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version")]
      File.write(File.join(dir, "versync.json"), JSON.generate(
                                                     "generated_at" => "2026-08-25T12:00:00Z", "commit" => "abc123",
                                                     "facts" => [{ "name" => "ruby", "value" => "4.0.6", "source" => ".ruby-version" }]
                                                   ))

      result = checker(dir).check(facts, rendered_markdown: fresh_markdown(facts))

      assert result.stale?
      assert result.markdown_stale
    end
  end

  def test_stale_when_json_facts_are_reordered
    with_temp_project do |dir|
      current = [
        Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version"),
        Versync::Fact.new(name: "rails", value: "8.1.3", source: "Gemfile.lock")
      ]
      # Same facts, written in reverse order — a real `sync` would never
      # produce this, but a hand-edited or merged versync.json might.
      File.write(File.join(dir, "versync.json"), JSON.generate(
                                                     "generated_at" => "2026-08-25T12:00:00Z", "commit" => "abc123",
                                                     "facts" => [
                                                       { "name" => "rails", "value" => "8.1.3", "source" => "Gemfile.lock" },
                                                       { "name" => "ruby", "value" => "4.0.6", "source" => ".ruby-version" }
                                                     ]
                                                   ))
      File.write(File.join(dir, "VERSIONS.md"), fresh_markdown(current))

      result = checker(dir).check(current, rendered_markdown: fresh_markdown(current))

      assert result.stale?
      refute_empty result.fact_diffs
    end
  end

  def test_stale_when_json_has_a_duplicate_fact_name_masking_the_real_value
    with_temp_project do |dir|
      current = [
        Versync::Fact.new(name: "rails", value: "8.1.3", source: "Gemfile.lock"),
        Versync::Fact.new(name: "postgres", value: "18", source: "compose.yaml (db)")
      ]
      # Duplicate "rails" entry where the second (wrong) occurrence would
      # win a name-keyed hash comparison — must still be caught as stale.
      File.write(File.join(dir, "versync.json"), JSON.generate(
                                                     "generated_at" => "2026-08-25T12:00:00Z", "commit" => "abc123",
                                                     "facts" => [
                                                       { "name" => "rails", "value" => "8.1.3", "source" => "Gemfile.lock" },
                                                       { "name" => "rails", "value" => "8.1.3", "source" => "Gemfile.lock" }
                                                     ]
                                                   ))
      File.write(File.join(dir, "VERSIONS.md"), fresh_markdown(current))

      result = checker(dir).check(current, rendered_markdown: fresh_markdown(current))

      assert result.stale?
      refute_empty result.fact_diffs
    end
  end

  def test_stale_when_versions_md_hand_edited
    with_temp_project do |dir|
      facts = [Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version")]
      File.write(File.join(dir, "versync.json"), JSON.generate(
                                                     "generated_at" => "2026-08-25T12:00:00Z", "commit" => "abc123",
                                                     "facts" => [{ "name" => "ruby", "value" => "4.0.6", "source" => ".ruby-version" }]
                                                   ))
      File.write(File.join(dir, "VERSIONS.md"), "# hand-edited, not what versync would render\n")

      result = checker(dir).check(facts, rendered_markdown: fresh_markdown(facts))

      assert result.stale?
      assert result.markdown_stale
    end
  end
end

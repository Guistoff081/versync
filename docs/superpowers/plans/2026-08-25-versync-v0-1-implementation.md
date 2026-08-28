# versync v0.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a working `versync` Ruby gem that extracts Ruby/Rails/Docker-Compose version facts from a project's own repository state and generates a canonical `VERSIONS.md` + `versync.json`, with a `check` command suitable for CI.

**Architecture:** Small isolated adapters (one per fact source) feed a `FactsCollector`, which produces a `Result` (successfully collected `Fact`s, plus a list of facts that were configured but unavailable). Two renderers turn the fact list into the canonical Markdown and JSON outputs. A `DiffChecker` compares freshly collected facts and a freshly rendered `VERSIONS.md` against what's on disk (ignoring the timestamp footer) to answer "is this stale?". A hand-rolled `CLI` class wires configuration, collection, rendering, and diffing together behind four subcommands.

**Tech Stack:** Ruby (gem, no Rails dependency), **Minitest** for tests (ships in the Ruby standard library — keeps the gem dependency-light and matches what `bundle gem` itself scaffolds by default), no external runtime dependencies beyond the Ruby standard library (`yaml`, `json`, `time`).

**Spec:** `docs/superpowers/specs/2026-08-25-versync-design.md`

## Global Constraints

- Gem name is `versync` (confirmed available on RubyGems as of 2026-08-25).
- No Rails dependency — must work in any Bundler-managed Ruby project.
- v0.1 ships exactly three adapters: `ruby_version`, `bundler`, `docker_compose`. No Node/JS fact sources.
- `sync` always fully regenerates `VERSIONS.md` and `versync.json` from scratch — never partial/in-place edits.
- No parsing or checking of arbitrary free-text docs (`README.md`, `CLAUDE.md`, `AGENTS.md`) in v0.1 — that's the deferred v0.2 marker design.
- No comparison against latest upstream releases (that's Renovate/Dependabot's job) — entirely out of scope, not just deferred.
- Tests use real temporary directories with fixture files copied in — no filesystem mocking.

## Design Decisions Not Explicit In The Spec

- **Timestamp footer excluded from staleness comparison.** The spec's illustrated `VERSIONS.md` includes a `_Last synced: <timestamp>_` line. If `check` compared full rendered file bytes against disk, it would report "stale" on every run purely because the timestamp changed. `DiffChecker` compares **structured fact data** (name/value/source) parsed from `versync.json`, and compares `VERSIONS.md` with the `_Last synced: ..._` line stripped from both sides — never raw file bytes.
- **Fact name capitalization.** The spec's illustrated table capitalizes fact names ("Ruby", "Rails"), but no display-name mapping is defined. The Markdown renderer prints the fact `name` exactly as configured (lowercase, e.g. `ruby`). A `label:` config addition is a future enhancement, not something to guess at now.
- **Unavailable facts are reported, not silently dropped.** The spec says a fact with no extractable value is "reported as unavailable rather than guessed" — silently vanishing from the output isn't reporting. `FactsCollector#collect` returns both the successfully collected facts and a list of skipped facts with reasons; `facts`/`sync` print one warning line per skipped fact to stderr. This never changes the exit code — an unavailable fact (e.g. no Redis configured) is an expected outcome.
- **`check` also validates `VERSIONS.md`, not just `versync.json`.** If only `versync.json` were compared, someone could hand-edit or delete `VERSIONS.md` — the file humans actually read — without `check` noticing. `DiffChecker` additionally renders a fresh Markdown body and compares it (footer-stripped) against what's on disk.
- **Compose file name.** The Compose Spec's own tooling now prefers `compose.yaml` over the legacy `docker-compose.yml`. The `docker_compose` adapter tries, in order: `compose.yaml`, `compose.yml`, `docker-compose.yaml`, `docker-compose.yml`, and reports whichever one it found as the fact's `source` (e.g. `compose.yaml (db)`).
- **YAML parsing needs `aliases: true`.** Real-world `docker-compose.yml`/`.versync.yml` files often use YAML anchors/aliases (`x-defaults: &defaults`). `YAML.safe_load(..., aliases: true)` is required everywhere the gem parses YAML, or it raises `Psych::AliasesNotEnabled` on any file using them.
- **`Time#iso8601` needs `require "time"`.** Without it, `Time#iso8601` raises `NoMethodError` on Ruby versions/builds where `Time` doesn't already have it loaded transitively. Both renderers require `"time"` explicitly.
- **`GitInfo` shells out without `Dir.chdir`.** Using `Dir.chdir` + backticks is not thread-safe (global process state) and needlessly changes the process's working directory. `git -C <project_root> rev-parse HEAD` passes the directory as an argument instead.
- **CLI error handling is command-specific, not one blanket rescue.** A single `rescue Errno::ENOENT` wrapping an entire command body would mis-attribute *any* `ENOENT` (e.g. from a broken symlink an adapter tries to read) to ".versync.yml not found". Each command explicitly checks `File.exist?(config_path)` up front, and rescues the specific `Configuration::InvalidError` / `FactsCollector::UnknownAdapterError` that can legitimately occur.
- **Malformed `.versync.yml` fails clearly.** A `facts:` entry with a `nil` body or no `adapter:` key would otherwise raise a confusing `NoMethodError`/`KeyError` deep in `Configuration`. It raises `Configuration::InvalidError` naming the offending fact instead.
- **Empty facts list renders cleanly.** Zero facts would otherwise produce a Markdown table with an empty body line. The renderer prints `_No facts available._` instead of an empty table when there are no facts.
- **Test class namespacing.** `class Adapters::FooTest < Minitest::Test` (compact form) requires the `Adapters`/`Renderers` constant to already exist at the top level — it does not auto-vivify like `module Adapters; class FooTest; end; end` does. Each affected test file either opens `module Adapters ... end` around the class, or predeclares `module Adapters; end` before the compact form. Confirmed by direct testing; the compact form without either fix raises `NameError: uninitialized constant Adapters`.
- **Fixture copying must handle dotfiles.** `Dir.glob("#{path}/*")` does **not** match dotfiles (`.ruby-version`, `.versync.yml`) by default in Ruby — confirmed by direct testing. `test_helper.rb`'s `copy_fixture` must pass `File::FNM_DOTMATCH` and filter out the `.`/`..` entries it then includes, or most fixtures silently fail to copy their most important file.
- **Facts are ordered by config, not by registry or alphabetically.** `FactsCollector#collect` iterates `fact_configs` in the order `Configuration` parsed them from `.versync.yml` (Ruby `Hash` preserves insertion order from YAML), and that order flows unchanged into both renderers.
- **`sync` validates output paths before writing anything.** `output.markdown`/`output.json` in `.versync.yml` are project-controlled, not adversary-controlled in the usual sense, but a `../` component, a path matching a fact's own source file (e.g. accidentally pointing `markdown` at `Gemfile.lock`), a path matching `.versync.yml` itself, identical markdown/json paths, or a path that is (or resolves through) a symlink would all let `sync` clobber a file it has no business touching. `CLI#output_path_error` rejects all of these up front and `write_atomically` writes via a temp file + `File.rename` so a failed write never leaves a half-written output in place.
- **`docker_compose` treats a digest without separating it from the tag, and unresolved variable interpolation, as reasons to report the fact unavailable rather than guess.** `image: postgres:16@sha256:...` must extract tag `16`, not the tail of the digest; `image: postgres@sha256:...` (digest-pinned, no tag) must report "no tag", not the digest hash. `extract_tag` splits off `@digest` before locating the tag-separating `:`. Separately, Compose interpolation (`${VAR}`, `${VAR:-default}`) is resolved by Compose itself, not by versync — an image string containing `$` after digest-splitting is treated as unresolvable and raises `NotFoundError` rather than emitting a value like `-16}` or a bare variable name.
- **`check` compares facts positionally, not by name.** Converting both fact lists to `{name => fact}` hashes before comparing silently collapses duplicate names (last one wins) and is blind to reordering — a `versync.json` with two "rails" entries, or the same facts in a different order, would pass every equality check a hash comparison performs. `DiffChecker#diff_facts` compares `on_disk_facts[i]` against `current_facts[i]` by index, so an out-of-order or duplicated on-disk entry it doesn't line up with the freshly collected fact is reported as a diff.

---

### Task 0: Documentation revisions

**Files:**
- Modify: `docs/superpowers/specs/2026-08-25-versync-design.md`
- Modify: `docs/superpowers/plans/2026-08-25-versync-v0-1-implementation.md` (this file)

- [ ] Apply the spec revisions described above (compose filename precedence, "Unavailable facts" subsection, full `check` staleness rules + exit-code table, Minitest rationale, `test/`/`Rakefile`/CI in repository structure, fact-ordering note).
- [ ] Commit:
```bash
git add docs/superpowers/specs/2026-08-25-versync-design.md docs/superpowers/plans/2026-08-25-versync-v0-1-implementation.md
git commit -m "Revise versync design spec and implementation plan"
```

---

### Task 1: Project scaffolding

**Files:**
- Create: `versync.gemspec`, `Gemfile`, `Rakefile`, `.gitignore`, `LICENSE.txt`
- Create: `lib/versync/version.rb`, `lib/versync.rb`
- Create: `.github/workflows/ci.yml`
- Create: `test/test_helper.rb`, `test/versync_test.rb`

**Interfaces:**
- Produces: `Versync::VERSION` (String constant). `with_temp_project(&block)` / `copy_fixture(fixture_name, project_root)` test helpers mixed into every `Minitest::Test`, used by every later task's tests.

- [ ] **Step 1: Create the gem skeleton files**

`versync.gemspec`:
```ruby
require_relative "lib/versync/version"

Gem::Specification.new do |spec|
  spec.name = "versync"
  spec.version = Versync::VERSION
  spec.authors = ["Elisson Guímel da Silva"]
  spec.email = ["guigolawliet13@gmail.com"]
  spec.summary = "Keeps documented repository facts (Ruby, Rails, service versions) in sync with reality."
  spec.description = "versync extracts version facts from a Ruby/Rails project's own repository state " \
                      "and generates a canonical VERSIONS.md/versync.json that both humans and AI agents " \
                      "can treat as ground truth."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  # TODO before `gem push`: spec.homepage + spec.metadata["source_code_uri"] once the repo has a public remote.

  spec.files = Dir["lib/**/*.rb", "exe/*", "LICENSE.txt", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["versync"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "rake", "~> 13.0"
end
```

`Gemfile`:
```ruby
source "https://rubygems.org"

gemspec
```

`Rakefile`:
```ruby
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.verbose = true
end

task default: :test
```

`.gitignore`:
```
/.bundle/
/Gemfile.lock
/pkg/
*.gem
```

`LICENSE.txt`:
```
MIT License

Copyright (c) 2026 Elisson Guímel da Silva

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

`.github/workflows/ci.yml`:
```yaml
name: CI

on:
  push:
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
          bundler-cache: true
      - run: bundle exec rake test
```

- [ ] **Step 2: Write the failing smoke test and test helper**

`test/test_helper.rb`:
```ruby
require "versync"
require "minitest/autorun"
require "tmpdir"
require "fileutils"

module VersyncTestHelpers
  def with_temp_project
    Dir.mktmpdir do |dir|
      yield dir
    end
  end

  # Dir.glob("#{path}/*") does NOT match dotfiles (e.g. .ruby-version,
  # .versync.yml) — most fixtures need exactly those files, so this
  # passes FNM_DOTMATCH and filters out "." and "..".
  def copy_fixture(fixture_name, project_root)
    fixture_path = File.join(__dir__, "fixtures", fixture_name)
    entries = Dir.glob("#{fixture_path}/*", File::FNM_DOTMATCH)
                 .reject { |entry| %w[. ..].include?(File.basename(entry)) }
    FileUtils.cp_r(entries, project_root)
  end
end

Minitest::Test.include(VersyncTestHelpers)
```

`test/versync_test.rb`:
```ruby
require "test_helper"

class VersyncTest < Minitest::Test
  def test_has_a_version_number
    refute_nil ::Versync::VERSION
  end
end
```

- [ ] **Step 3: Run the test suite to verify it fails**

Run: `bundle install && bundle exec rake test`
Expected: FAIL — `LoadError: cannot load such file -- versync`.

- [ ] **Step 4: Create the minimal library entry point**

`lib/versync/version.rb`:
```ruby
module Versync
  VERSION = "0.1.0"
end
```

`lib/versync.rb`:
```ruby
require_relative "versync/version"

module Versync
end
```

- [ ] **Step 5: Run the test suite to verify it passes**

Run: `bundle exec rake test`
Expected: PASS (1 run, 1 assertion, 0 failures).

- [ ] **Step 6: Commit**

```bash
git add versync.gemspec Gemfile Rakefile .gitignore LICENSE.txt lib .github test
git commit -m "Scaffold versync gem with Minitest harness"
```

---

### Task 2: `Fact` value object and `Adapters::Base` interface

**Files:**
- Create: `lib/versync/fact.rb`, `lib/versync/adapters/base.rb`
- Modify: `lib/versync.rb`
- Test: `test/fact_test.rb`, `test/adapters/base_test.rb`

**Interfaces:**
- Produces: `Versync::Fact.new(name:, value:, source:)` (keyword-init Struct, comparable by value). `Versync::Adapters::Base` — abstract adapter with `#name`, `#available?(project_root)`, `#extract(project_root, options)`, all raising `NotImplementedError`. `Versync::Adapters::NotFoundError` — raised by concrete adapters when a fact cannot be extracted.

- [ ] **Step 1: Write the failing tests**

`test/fact_test.rb`:
```ruby
require "test_helper"

class FactTest < Minitest::Test
  def test_value_equality
    a = Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version")
    b = Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version")

    assert_equal a, b
  end
end
```

`test/adapters/base_test.rb`:
```ruby
require "test_helper"

# NOTE: `Adapters` here must be opened with `module ... end`, not the
# compact `class Adapters::BaseTest` form — the compact form requires
# the `Adapters` constant to already exist, which it doesn't at the
# top level (only inside `Versync::Adapters`).
module Adapters
  class BaseTest < Minitest::Test
    def setup
      @adapter = Versync::Adapters::Base.new
    end

    def test_name_raises
      assert_raises(NotImplementedError) { @adapter.name }
    end

    def test_available_raises
      assert_raises(NotImplementedError) { @adapter.available?("/some/root") }
    end

    def test_extract_raises
      assert_raises(NotImplementedError) { @adapter.extract("/some/root", {}) }
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rake test`
Expected: FAIL — `uninitialized constant Versync::Fact` / `Versync::Adapters`.

- [ ] **Step 3: Implement**

`lib/versync/fact.rb`:
```ruby
module Versync
  Fact = Struct.new(:name, :value, :source, keyword_init: true)
end
```

`lib/versync/adapters/base.rb`:
```ruby
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
```

Add to `lib/versync.rb`:
```ruby
require_relative "versync/fact"
require_relative "versync/adapters/base"
```

- [ ] **Step 4: Run to verify pass** — `bundle exec rake test` PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/fact.rb lib/versync/adapters/base.rb lib/versync.rb test/fact_test.rb test/adapters/base_test.rb
git commit -m "Add Fact value object and Adapters::Base interface"
```

---

### Task 3: `ruby_version` adapter

**Files:**
- Create: `lib/versync/adapters/ruby_version.rb`, `test/fixtures/ruby_project/.ruby-version`
- Modify: `lib/versync.rb`
- Test: `test/adapters/ruby_version_test.rb`

**Interfaces:**
- Produces: `Versync::Adapters::RubyVersion.new.extract(project_root, options)` → `{ value: "4.0.6", source: ".ruby-version" }`. Registered under `"ruby_version"` in `FactsCollector`'s registry (Task 7).

- [ ] **Step 1: Write the failing test and fixture**

`test/fixtures/ruby_project/.ruby-version`:
```
4.0.6
```

`test/adapters/ruby_version_test.rb`:
```ruby
require "test_helper"

module Adapters; end # see note in test/adapters/base_test.rb about this compact-form requirement

class Adapters::RubyVersionTest < Minitest::Test
  def setup
    @adapter = Versync::Adapters::RubyVersion.new
  end

  def test_available_when_ruby_version_exists
    with_temp_project do |dir|
      copy_fixture("ruby_project", dir)
      assert @adapter.available?(dir)
    end
  end

  def test_not_available_when_ruby_version_missing
    with_temp_project { |dir| refute @adapter.available?(dir) }
  end

  def test_extracts_ruby_version_stripped
    with_temp_project do |dir|
      copy_fixture("ruby_project", dir)
      assert_equal({ value: "4.0.6", source: ".ruby-version" }, @adapter.extract(dir, {}))
    end
  end

  def test_raises_not_found_when_missing
    with_temp_project do |dir|
      assert_raises(Versync::Adapters::NotFoundError) { @adapter.extract(dir, {}) }
    end
  end
end
```

- [ ] **Step 2: Run to verify failure** — `uninitialized constant Versync::Adapters::RubyVersion`.

- [ ] **Step 3: Implement**

`lib/versync/adapters/ruby_version.rb`:
```ruby
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
```

Add to `lib/versync.rb`: `require_relative "versync/adapters/ruby_version"`

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/adapters/ruby_version.rb lib/versync.rb test/adapters/ruby_version_test.rb test/fixtures/ruby_project
git commit -m "Add ruby_version adapter"
```

---

### Task 4: `bundler` adapter

**Files:**
- Create: `lib/versync/adapters/bundler.rb`, `test/fixtures/bundler_project/Gemfile.lock`
- Modify: `lib/versync.rb`
- Test: `test/adapters/bundler_test.rb`

**Interfaces:**
- Produces: `Versync::Adapters::Bundler.new.extract(project_root, { "gem" => "rails" })` → `{ value: "8.1.3", source: "Gemfile.lock" }`. Registered under `"bundler"` in `FactsCollector`'s registry.

- [ ] **Step 1: Write the failing test and fixture**

`test/fixtures/bundler_project/Gemfile.lock`:
```
GEM
  remote: https://rubygems.org/
  specs:
    concurrent-ruby (1.2.2)
    i18n (1.14.1)
      concurrent-ruby (~> 1.0)
    rails (8.1.3)
      actionpack (= 8.1.3)
      activesupport (= 8.1.3)
    rake (13.1.0)

PLATFORMS
  ruby

DEPENDENCIES
  rails

BUNDLED WITH
   2.5.3
```

`test/adapters/bundler_test.rb`:
```ruby
require "test_helper"

module Adapters; end # see note in test/adapters/base_test.rb about this compact-form requirement

class Adapters::BundlerTest < Minitest::Test
  def setup
    @adapter = Versync::Adapters::Bundler.new
    @dir = Dir.mktmpdir
    copy_fixture("bundler_project", @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_available_when_gemfile_lock_exists
    assert @adapter.available?(@dir)
  end

  def test_extracts_top_level_gem_version
    assert_equal({ value: "8.1.3", source: "Gemfile.lock" }, @adapter.extract(@dir, { "gem" => "rails" }))
  end

  def test_does_not_match_nested_dependency_constraints
    assert_equal({ value: "1.2.2", source: "Gemfile.lock" }, @adapter.extract(@dir, { "gem" => "concurrent-ruby" }))
  end

  def test_raises_not_found_when_gem_missing
    assert_raises(Versync::Adapters::NotFoundError) { @adapter.extract(@dir, { "gem" => "sidekiq" }) }
  end

  def test_raises_not_found_when_no_gem_option
    assert_raises(Versync::Adapters::NotFoundError) { @adapter.extract(@dir, {}) }
  end
end
```

- [ ] **Step 2: Run to verify failure** — `uninitialized constant Versync::Adapters::Bundler`.

- [ ] **Step 3: Implement**

`lib/versync/adapters/bundler.rb`:
```ruby
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
```

Add to `lib/versync.rb`: `require_relative "versync/adapters/bundler"`

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/adapters/bundler.rb lib/versync.rb test/adapters/bundler_test.rb test/fixtures/bundler_project
git commit -m "Add bundler adapter"
```

---

### Task 5: `docker_compose` adapter

**Files:**
- Create: `lib/versync/adapters/docker_compose.rb`
- Create: `test/fixtures/docker_compose_project/compose.yaml`, `test/fixtures/docker_compose_project_legacy_name/docker-compose.yml`, `test/fixtures/docker_compose_project_with_anchors/compose.yaml`
- Modify: `lib/versync.rb`
- Test: `test/adapters/docker_compose_test.rb`

**Interfaces:**
- Produces: `Versync::Adapters::DockerCompose.new.extract(project_root, { "service" => "db" })` → `{ value: "18.1-alpine", source: "compose.yaml (db)" }`. `Versync::Adapters::DockerCompose::CANDIDATE_FILENAMES` (also used by the CLI's `init` probing, Task 15). Registered under `"docker_compose"` in `FactsCollector`'s registry.

- [ ] **Step 1: Write the failing tests and fixtures**

`test/fixtures/docker_compose_project/compose.yaml`:
```yaml
services:
  db:
    image: postgres:18.1-alpine
  redis:
    image: redis:8.2
  no_tag:
    image: postgres
  built:
    build: .
  registry_no_tag:
    image: myregistry:5000/postgres
  registry_tag:
    image: myregistry:5000/postgres:18
```

`test/fixtures/docker_compose_project_legacy_name/docker-compose.yml`:
```yaml
services:
  db:
    image: postgres:16.4
```

`test/fixtures/docker_compose_project_with_anchors/compose.yaml`:
```yaml
x-defaults: &defaults
  restart: unless-stopped

services:
  db:
    <<: *defaults
    image: postgres:18.1-alpine
```

`test/adapters/docker_compose_test.rb`:
```ruby
require "test_helper"

module Adapters; end # see note in test/adapters/base_test.rb about this compact-form requirement

class Adapters::DockerComposeTest < Minitest::Test
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
```

- [ ] **Step 2: Run to verify failure** — `uninitialized constant Versync::Adapters::DockerCompose`.

- [ ] **Step 3: Implement**

`lib/versync/adapters/docker_compose.rb`:
```ruby
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
      # "5000/postgres" as the tag.
      def extract_tag(image)
        last_slash = image.rindex("/") || -1
        last_colon = image.rindex(":")
        return nil unless last_colon && last_colon > last_slash

        image[(last_colon + 1)..]
      end
    end
  end
end
```

Add to `lib/versync.rb`: `require_relative "versync/adapters/docker_compose"`

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/adapters/docker_compose.rb lib/versync.rb test/adapters/docker_compose_test.rb \
        test/fixtures/docker_compose_project test/fixtures/docker_compose_project_legacy_name \
        test/fixtures/docker_compose_project_with_anchors
git commit -m "Add docker_compose adapter"
```

---

### Task 6: `Configuration`

**Files:**
- Create: `lib/versync/configuration.rb`, `test/fixtures/config_project/.versync.yml`
- Modify: `lib/versync.rb`
- Test: `test/configuration_test.rb`

**Interfaces:**
- Produces: `Versync::Configuration.load(path)` → instance with `#markdown_output`, `#json_output`, `#fact_configs` (Array of `Versync::Configuration::FactConfig`, keyword-init Struct `:name, :adapter, :options`, in config file order). Raises `Errno::ENOENT` if `path` doesn't exist, `Versync::Configuration::InvalidError` if a fact entry is malformed.

- [ ] **Step 1: Write the failing test and fixture**

`test/fixtures/config_project/.versync.yml`:
```yaml
output:
  markdown: VERSIONS.md
  json: versync.json

facts:
  ruby:
    adapter: ruby_version
  rails:
    adapter: bundler
    gem: rails
  postgres:
    adapter: docker_compose
    service: db
```

`test/configuration_test.rb`:
```ruby
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
```

- [ ] **Step 2: Run to verify failure** — `uninitialized constant Versync::Configuration`.

- [ ] **Step 3: Implement**

`lib/versync/configuration.rb`:
```ruby
require "yaml"

module Versync
  class Configuration
    class InvalidError < StandardError; end

    FactConfig = Struct.new(:name, :adapter, :options, keyword_init: true)

    DEFAULT_MARKDOWN_OUTPUT = "VERSIONS.md"
    DEFAULT_JSON_OUTPUT = "versync.json"

    attr_reader :markdown_output, :json_output, :fact_configs

    def self.load(path)
      raise Errno::ENOENT, path unless File.exist?(path)

      data = YAML.safe_load(File.read(path), aliases: true) || {}
      new(data)
    end

    def initialize(data)
      output = data.fetch("output", {}) || {}
      @markdown_output = output.fetch("markdown", DEFAULT_MARKDOWN_OUTPUT)
      @json_output = output.fetch("json", DEFAULT_JSON_OUTPUT)

      @fact_configs = (data.fetch("facts", {}) || {}).map do |fact_name, fact_data|
        unless fact_data.is_a?(Hash) && fact_data["adapter"]
          raise InvalidError, "fact '#{fact_name}' is missing an 'adapter' key"
        end

        options = fact_data.reject { |key, _| key == "adapter" }
        FactConfig.new(name: fact_name, adapter: fact_data["adapter"], options: options)
      end
    end
  end
end
```

Add to `lib/versync.rb`: `require_relative "versync/configuration"`

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/configuration.rb lib/versync.rb test/configuration_test.rb test/fixtures/config_project
git commit -m "Add Configuration for .versync.yml"
```

---

### Task 7: `FactsCollector`

**Files:**
- Create: `lib/versync/facts_collector.rb`
- Modify: `lib/versync.rb`
- Test: `test/facts_collector_test.rb`

**Interfaces:**
- Produces: `Versync::FactsCollector.new(adapter_registry: ...).collect(project_root, fact_configs)` → `Versync::FactsCollector::Result` (keyword-init Struct: `facts` Array<Fact>, `skipped` Array<Skipped>). `Skipped` is a keyword-init Struct `:name, :reason`. `Versync::FactsCollector::UnknownAdapterError`. The default registry maps `"ruby_version"`, `"bundler"`, `"docker_compose"` to the Task 3–5 adapters.

- [ ] **Step 1: Write the failing test**

`test/facts_collector_test.rb`:
```ruby
require "test_helper"

class FactsCollectorTest < Minitest::Test
  def setup
    success_adapter = Class.new(Versync::Adapters::Base) do
      def extract(project_root, options)
        { value: "1.2.3", source: "fake" }
      end
    end.new

    not_found_adapter = Class.new(Versync::Adapters::Base) do
      def extract(project_root, options)
        raise Versync::Adapters::NotFoundError, "nope"
      end
    end.new

    registry = { "fake_success" => -> { success_adapter }, "fake_not_found" => -> { not_found_adapter } }
    @collector = Versync::FactsCollector.new(adapter_registry: registry)
  end

  def test_collects_facts_from_successful_adapters
    configs = [Versync::Configuration::FactConfig.new(name: "ruby", adapter: "fake_success", options: {})]
    result = @collector.collect("/fake/root", configs)

    assert_equal [Versync::Fact.new(name: "ruby", value: "1.2.3", source: "fake")], result.facts
    assert_empty result.skipped
  end

  def test_reports_skipped_facts_whose_adapter_raises_not_found
    configs = [Versync::Configuration::FactConfig.new(name: "missing", adapter: "fake_not_found", options: {})]
    result = @collector.collect("/fake/root", configs)

    assert_empty result.facts
    assert_equal 1, result.skipped.size
    assert_equal "missing", result.skipped.first.name
    assert_equal "nope", result.skipped.first.reason
  end

  def test_raises_unknown_adapter_error
    configs = [Versync::Configuration::FactConfig.new(name: "x", adapter: "nope", options: {})]

    assert_raises(Versync::FactsCollector::UnknownAdapterError) { @collector.collect("/fake/root", configs) }
  end

  def test_default_registry_covers_the_three_shipped_adapters
    default_collector = Versync::FactsCollector.new
    configs = [Versync::Configuration::FactConfig.new(name: "ruby", adapter: "ruby_version", options: {})]

    with_temp_project do |dir|
      copy_fixture("ruby_project", dir)
      result = default_collector.collect(dir, configs)
      assert_equal [Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version")], result.facts
    end
  end

  def test_preserves_config_order_in_facts
    configs = [
      Versync::Configuration::FactConfig.new(name: "b", adapter: "fake_success", options: {}),
      Versync::Configuration::FactConfig.new(name: "a", adapter: "fake_success", options: {})
    ]
    result = @collector.collect("/fake/root", configs)

    assert_equal %w[b a], result.facts.map(&:name)
  end
end
```

- [ ] **Step 2: Run to verify failure** — `uninitialized constant Versync::FactsCollector`.

- [ ] **Step 3: Implement**

`lib/versync/facts_collector.rb`:
```ruby
module Versync
  class FactsCollector
    class UnknownAdapterError < StandardError; end

    Result = Struct.new(:facts, :skipped, keyword_init: true)
    Skipped = Struct.new(:name, :reason, keyword_init: true)

    DEFAULT_ADAPTER_REGISTRY = {
      "ruby_version" => -> { Adapters::RubyVersion.new },
      "bundler" => -> { Adapters::Bundler.new },
      "docker_compose" => -> { Adapters::DockerCompose.new }
    }.freeze

    def initialize(adapter_registry: DEFAULT_ADAPTER_REGISTRY)
      @adapter_registry = adapter_registry
    end

    # Returns a Result. Fact configs whose adapter raises
    # Adapters::NotFoundError are reported in `skipped`, not raised —
    # an unavailable fact (e.g. no Redis configured) is expected, not
    # a failure. An unregistered adapter name is a configuration bug
    # and does raise.
    def collect(project_root, fact_configs)
      facts = []
      skipped = []

      fact_configs.each do |fact_config|
        adapter = build_adapter(fact_config.adapter)
        begin
          result = adapter.extract(project_root, fact_config.options)
          facts << Fact.new(name: fact_config.name, value: result.fetch(:value), source: result.fetch(:source))
        rescue Adapters::NotFoundError => e
          skipped << Skipped.new(name: fact_config.name, reason: e.message)
        end
      end

      Result.new(facts: facts, skipped: skipped)
    end

    private

    def build_adapter(adapter_name)
      factory = @adapter_registry.fetch(adapter_name) do
        raise UnknownAdapterError, "unknown adapter '#{adapter_name}'"
      end
      factory.call
    end
  end
end
```

Add to `lib/versync.rb`: `require_relative "versync/facts_collector"`

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/facts_collector.rb lib/versync.rb test/facts_collector_test.rb
git commit -m "Add FactsCollector orchestrating adapters"
```

---

### Task 8: `GitInfo`

**Files:**
- Create: `lib/versync/git_info.rb`
- Modify: `lib/versync.rb`
- Test: `test/git_info_test.rb`

**Interfaces:**
- Produces: `Versync::GitInfo.current_sha(project_root)` → 40-character SHA String, or `nil` if not a git repository, no commits yet, or `git` isn't installed.

- [ ] **Step 1: Write the failing test**

`test/git_info_test.rb`:
```ruby
require "test_helper"

class GitInfoTest < Minitest::Test
  def test_returns_head_sha_for_a_git_repository
    with_temp_project do |dir|
      system("git", "-C", dir, "init", "-q")
      system("git", "-C", dir, "config", "user.email", "test@example.com")
      system("git", "-C", dir, "config", "user.name", "Test")
      File.write(File.join(dir, "file.txt"), "content")
      system("git", "-C", dir, "add", "file.txt")
      system("git", "-C", dir, "commit", "-q", "-m", "initial")

      sha = Versync::GitInfo.current_sha(dir)

      assert_match(/\A[0-9a-f]{40}\z/, sha)
    end
  end

  def test_returns_nil_when_not_a_git_repository
    with_temp_project { |dir| assert_nil Versync::GitInfo.current_sha(dir) }
  end
end
```

- [ ] **Step 2: Run to verify failure** — `uninitialized constant Versync::GitInfo`.

- [ ] **Step 3: Implement**

`lib/versync/git_info.rb`:
```ruby
module Versync
  module GitInfo
    def self.current_sha(project_root)
      sha = `git -C #{project_root.shellescape} rev-parse HEAD 2>/dev/null`.strip
      sha.empty? ? nil : sha
    rescue Errno::ENOENT
      nil
    end
  end
end
```

Add `require "shellwords"` to `lib/versync.rb` before this require, and:
```ruby
require_relative "versync/git_info"
```

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/git_info.rb lib/versync.rb test/git_info_test.rb
git commit -m "Add GitInfo.current_sha"
```

---

### Task 9: `Renderers::Json`

**Files:**
- Create: `lib/versync/renderers/json.rb`
- Modify: `lib/versync.rb`
- Test: `test/renderers/json_test.rb`

**Interfaces:**
- Produces: `Versync::Renderers::Json.new(facts:, generated_at:, commit:).render` → JSON String with `"generated_at"` (ISO 8601), `"commit"` (String or `null`), `"facts"` (Array of `{"name", "value", "source"}`, in the order given).

- [ ] **Step 1: Write the failing test**

`test/renderers/json_test.rb`:
```ruby
require "test_helper"
require "json"
require "time"

module Renderers; end # see note in test/adapters/base_test.rb about this compact-form requirement

class Renderers::JsonTest < Minitest::Test
  def test_renders_facts_generated_at_and_commit
    facts = [Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version")]
    generated_at = Time.parse("2026-08-25T12:00:00Z")

    output = Versync::Renderers::Json.new(facts: facts, generated_at: generated_at, commit: "abc123").render
    parsed = JSON.parse(output)

    assert_equal(
      {
        "generated_at" => "2026-08-25T12:00:00Z",
        "commit" => "abc123",
        "facts" => [{ "name" => "ruby", "value" => "4.0.6", "source" => ".ruby-version" }]
      },
      parsed
    )
  end

  def test_renders_null_commit_when_none_given
    output = Versync::Renderers::Json.new(facts: [], generated_at: Time.parse("2026-08-25T12:00:00Z"), commit: nil).render
    assert_nil JSON.parse(output)["commit"]
  end
end
```

- [ ] **Step 2: Run to verify failure** — `uninitialized constant Versync::Renderers`.

- [ ] **Step 3: Implement**

`lib/versync/renderers/json.rb`:
```ruby
require "json"
require "time"

module Versync
  module Renderers
    class Json
      def initialize(facts:, generated_at:, commit:)
        @facts = facts
        @generated_at = generated_at
        @commit = commit
      end

      def render
        JSON.pretty_generate(
          "generated_at" => @generated_at.utc.iso8601,
          "commit" => @commit,
          "facts" => @facts.map { |fact| { "name" => fact.name, "value" => fact.value, "source" => fact.source } }
        )
      end
    end
  end
end
```

Add to `lib/versync.rb`: `require_relative "versync/renderers/json"`

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/renderers/json.rb lib/versync.rb test/renderers/json_test.rb
git commit -m "Add JSON renderer"
```

---

### Task 10: `Renderers::Markdown`

**Files:**
- Create: `lib/versync/renderers/markdown.rb`
- Modify: `lib/versync.rb`
- Test: `test/renderers/markdown_test.rb`

**Interfaces:**
- Produces: `Versync::Renderers::Markdown.new(facts:, generated_at:, commit:).render` → Markdown String. Renders `_No facts available._` instead of a table when `facts` is empty.

- [ ] **Step 1: Write the failing test**

`test/renderers/markdown_test.rb`:
```ruby
require "test_helper"
require "time"

module Renderers; end # see note in test/adapters/base_test.rb about this compact-form requirement

class Renderers::MarkdownTest < Minitest::Test
  def test_renders_a_facts_table_with_header_and_footer
    facts = [
      Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version"),
      Versync::Fact.new(name: "rails", value: "8.1.3", source: "Gemfile.lock")
    ]
    generated_at = Time.parse("2026-08-25T12:00:00Z")

    output = Versync::Renderers::Markdown.new(facts: facts, generated_at: generated_at, commit: "abc123").render

    assert_includes output, "<!-- Generated by versync. Do not edit by hand — run `versync sync`. -->"
    assert_includes output, "| Fact | Version | Source |"
    assert_includes output, "| ruby | 4.0.6 | .ruby-version |"
    assert_includes output, "| rails | 8.1.3 | Gemfile.lock |"
    assert_includes output, "_Last synced: 2026-08-25T12:00:00Z · commit abc123_"
  end

  def test_renders_unknown_when_commit_is_nil
    output = Versync::Renderers::Markdown.new(facts: [], generated_at: Time.parse("2026-08-25T12:00:00Z"), commit: nil).render
    assert_includes output, "commit unknown"
  end

  def test_renders_placeholder_when_no_facts
    output = Versync::Renderers::Markdown.new(facts: [], generated_at: Time.parse("2026-08-25T12:00:00Z"), commit: "abc").render
    assert_includes output, "_No facts available._"
    refute_includes output, "| Fact | Version | Source |"
  end
end
```

- [ ] **Step 2: Run to verify failure** — `uninitialized constant Versync::Renderers::Markdown`.

- [ ] **Step 3: Implement**

`lib/versync/renderers/markdown.rb`:
```ruby
require "time"

module Versync
  module Renderers
    class Markdown
      HEADER = "<!-- Generated by versync. Do not edit by hand — run `versync sync`. -->"

      def initialize(facts:, generated_at:, commit:)
        @facts = facts
        @generated_at = generated_at
        @commit = commit
      end

      def render
        <<~MD
          #{HEADER}

          # Repository Facts

          #{table}

          _Last synced: #{@generated_at.utc.iso8601} · commit #{@commit || "unknown"}_
        MD
      end

      private

      def table
        return "_No facts available._" if @facts.empty?

        rows = @facts.map { |fact| "| #{fact.name} | #{fact.value} | #{fact.source} |" }
        (["| Fact | Version | Source |", "|---|---|---|"] + rows).join("\n")
      end
    end
  end
end
```

Add to `lib/versync.rb`: `require_relative "versync/renderers/markdown"`

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/renderers/markdown.rb lib/versync.rb test/renderers/markdown_test.rb
git commit -m "Add Markdown renderer"
```

---

### Task 11: `DiffChecker`

**Files:**
- Create: `lib/versync/diff_checker.rb`
- Modify: `lib/versync.rb`
- Test: `test/diff_checker_test.rb`

**Interfaces:**
- Produces: `Versync::DiffChecker.new(project_root:, json_output:, markdown_output:).check(current_facts, rendered_markdown:)` → `Versync::DiffChecker::Result` (keyword-init Struct: `stale?` Boolean, `missing_output` Boolean, `fact_diffs` Array of `{name:, before:, after:}`, `markdown_stale` Boolean). Compares structured facts from `versync.json` (ignoring `generated_at`/`commit`) and compares `VERSIONS.md` on disk against `rendered_markdown` with the `_Last synced: ..._` footer line stripped from both.

- [ ] **Step 1: Write the failing test**

`test/diff_checker_test.rb`:
```ruby
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
```

- [ ] **Step 2: Run to verify failure** — `uninitialized constant Versync::DiffChecker`.

- [ ] **Step 3: Implement**

`lib/versync/diff_checker.rb`:
```ruby
require "json"

module Versync
  class DiffChecker
    Result = Struct.new(:stale?, :missing_output, :fact_diffs, :markdown_stale, keyword_init: true)

    FOOTER_PATTERN = /^_Last synced:.*_\n?/

    def initialize(project_root:, json_output:, markdown_output:)
      @project_root = project_root
      @json_output = json_output
      @markdown_output = markdown_output
    end

    def check(current_facts, rendered_markdown:)
      json_path = File.join(@project_root, @json_output)
      unless File.exist?(json_path)
        return Result.new(stale?: true, missing_output: true, fact_diffs: [], markdown_stale: true)
      end

      on_disk = JSON.parse(File.read(json_path))
      on_disk_facts = on_disk.fetch("facts", []).map do |f|
        Fact.new(name: f["name"], value: f["value"], source: f["source"])
      end

      fact_diffs = diff_facts(on_disk_facts, current_facts)
      markdown_stale = markdown_stale?(rendered_markdown)

      Result.new(
        stale?: !fact_diffs.empty? || markdown_stale,
        missing_output: false,
        fact_diffs: fact_diffs,
        markdown_stale: markdown_stale
      )
    end

    private

    def markdown_stale?(rendered_markdown)
      markdown_path = File.join(@project_root, @markdown_output)
      return true unless File.exist?(markdown_path)

      strip_footer(File.read(markdown_path)) != strip_footer(rendered_markdown)
    end

    def strip_footer(text)
      text.sub(FOOTER_PATTERN, "")
    end

    def diff_facts(on_disk_facts, current_facts)
      on_disk_by_name = on_disk_facts.to_h { |f| [f.name, f] }
      current_by_name = current_facts.to_h { |f| [f.name, f] }
      names = (on_disk_by_name.keys | current_by_name.keys)

      names.filter_map do |name|
        before = on_disk_by_name[name]
        after = current_by_name[name]
        next nil if before && after && before.value == after.value && before.source == after.source

        { name: name, before: before&.value, after: after&.value }
      end
    end
  end
end
```

Add to `lib/versync.rb`: `require_relative "versync/diff_checker"`

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/diff_checker.rb lib/versync.rb test/diff_checker_test.rb
git commit -m "Add DiffChecker comparing structured facts and rendered Markdown body"
```

---

### Task 12: CLI skeleton, `exe/versync`, and `facts` command

**Files:**
- Create: `lib/versync/cli.rb`, `exe/versync`
- Create: `test/fixtures/full_project/.ruby-version`, `Gemfile.lock`, `compose.yaml`, `.versync.yml`
- Modify: `lib/versync.rb`
- Test: `test/cli_test.rb`

**Interfaces:**
- Produces: `Versync::CLI.new(argv, project_root: Dir.pwd, stdout: $stdout, stderr: $stderr).run` → Integer exit code, dispatching on `argv.first` to `init`/`facts`/`sync`/`check`. This task implements `facts` for real; `sync`/`check`/`init` are stubs returning `1`, replaced in Tasks 13–15 without changing this class's public interface.

- [ ] **Step 1: Write the failing test and fixtures**

`test/fixtures/full_project/.ruby-version`:
```
4.0.6
```

`test/fixtures/full_project/Gemfile.lock`:
```
GEM
  remote: https://rubygems.org/
  specs:
    rails (8.1.3)
      actionpack (= 8.1.3)

PLATFORMS
  ruby

DEPENDENCIES
  rails

BUNDLED WITH
   2.5.3
```

`test/fixtures/full_project/compose.yaml`:
```yaml
services:
  db:
    image: postgres:18.1-alpine
  redis:
    image: redis:8.2
```

`test/fixtures/full_project/.versync.yml`:
```yaml
facts:
  ruby:
    adapter: ruby_version
  rails:
    adapter: bundler
    gem: rails
  postgres:
    adapter: docker_compose
    service: db
  redis:
    adapter: docker_compose
    service: redis
```

`test/cli_test.rb`:
```ruby
require "test_helper"
require "stringio"

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
```

- [ ] **Step 2: Run to verify failure** — `uninitialized constant Versync::CLI`.

- [ ] **Step 3: Implement**

`lib/versync/cli.rb`:
```ruby
require "yaml"
require "time"

module Versync
  class CLI
    COMMANDS = %w[init facts sync check].freeze

    def initialize(argv, project_root: Dir.pwd, stdout: $stdout, stderr: $stderr)
      @argv = argv
      @project_root = project_root
      @stdout = stdout
      @stderr = stderr
    end

    def run
      command = @argv.first
      unless COMMANDS.include?(command)
        @stderr.puts "Usage: versync [#{COMMANDS.join('|')}]"
        return 1
      end

      send("run_#{command}")
    end

    private

    attr_reader :project_root

    def config_path
      File.join(project_root, ".versync.yml")
    end

    # Returns a loaded Configuration, or nil after printing a diagnostic
    # to stderr — callers return 1 when this returns nil.
    def load_config
      unless File.exist?(config_path)
        @stderr.puts ".versync.yml not found — run `versync init` first"
        return nil
      end

      Configuration.load(config_path)
    rescue Configuration::InvalidError => e
      @stderr.puts ".versync.yml is invalid: #{e.message}"
      nil
    end

    # Returns a FactsCollector::Result, or nil after printing a
    # diagnostic to stderr.
    def collect_facts(config)
      FactsCollector.new.collect(project_root, config.fact_configs)
    rescue FactsCollector::UnknownAdapterError => e
      @stderr.puts e.message
      nil
    end

    def warn_skipped(skipped)
      skipped.each { |s| @stderr.puts "warning: fact '#{s.name}' unavailable — #{s.reason}" }
    end

    def run_facts
      config = load_config
      return 1 unless config

      result = collect_facts(config)
      return 1 unless result

      result.facts.each { |fact| @stdout.puts "#{fact.name}: #{fact.value} (#{fact.source})" }
      warn_skipped(result.skipped)
      0
    end

    def run_sync
      1
    end

    def run_check
      1
    end

    def run_init
      1
    end
  end
end
```

`exe/versync`:
```ruby
#!/usr/bin/env ruby

require "versync"

exit Versync::CLI.new(ARGV).run
```

Make it executable: `chmod +x exe/versync`

Add to `lib/versync.rb`: `require_relative "versync/cli"`

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/cli.rb exe/versync lib/versync.rb test/cli_test.rb test/fixtures/full_project
git commit -m "Add CLI skeleton, exe/versync, and facts command"
```

---

### Task 13: CLI `sync` command

**Files:**
- Modify: `lib/versync/cli.rb` (replace the `run_sync` stub)
- Modify: `test/cli_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/cli_test.rb`:
```ruby
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
```

Add `require "json"` near the top of `test/cli_test.rb`.

- [ ] **Step 2: Run to verify failure** — `status` is `1` instead of `0`.

- [ ] **Step 3: Implement**

Replace `run_sync` in `lib/versync/cli.rb`:
```ruby
    def run_sync
      config = load_config
      return 1 unless config

      result = collect_facts(config)
      return 1 unless result

      generated_at = Time.now
      commit = GitInfo.current_sha(project_root)

      markdown = Renderers::Markdown.new(facts: result.facts, generated_at: generated_at, commit: commit).render
      json = Renderers::Json.new(facts: result.facts, generated_at: generated_at, commit: commit).render

      File.write(File.join(project_root, config.markdown_output), markdown)
      File.write(File.join(project_root, config.json_output), json)

      warn_skipped(result.skipped)
      @stdout.puts "Synced #{result.facts.size} fact(s) to #{config.markdown_output} and #{config.json_output}"
      0
    end
```

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/cli.rb test/cli_test.rb
git commit -m "Implement versync sync command"
```

---

### Task 14: CLI `check` command

**Files:**
- Modify: `lib/versync/cli.rb` (replace the `run_check` stub)
- Modify: `test/cli_test.rb`

- [ ] **Step 1: Write the failing test**

Add to `test/cli_test.rb`:
```ruby
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
```

- [ ] **Step 2: Run to verify failure** — stub always returns `1`, so "returns 0 after a sync" fails.

- [ ] **Step 3: Implement**

Replace `run_check` in `lib/versync/cli.rb`:
```ruby
    def run_check
      config = load_config
      return 1 unless config

      result = collect_facts(config)
      return 1 unless result

      rendered_markdown = Renderers::Markdown.new(
        facts: result.facts, generated_at: Time.now, commit: GitInfo.current_sha(project_root)
      ).render

      diff = DiffChecker.new(
        project_root: project_root, json_output: config.json_output, markdown_output: config.markdown_output
      ).check(result.facts, rendered_markdown: rendered_markdown)

      warn_skipped(result.skipped)

      if diff.stale?
        @stderr.puts "versync is stale — run `versync sync`:"
        @stderr.puts "  #{config.json_output} does not exist" if diff.missing_output
        if diff.markdown_stale && !diff.missing_output
          @stderr.puts "  #{config.markdown_output} is missing or out of date"
        end
        diff.fact_diffs.each do |d|
          @stderr.puts "  #{d[:name]}: documented=#{d[:before].inspect} actual=#{d[:after].inspect}"
        end
        return 1
      end

      @stdout.puts "versync is up to date"
      0
    end
```

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/cli.rb test/cli_test.rb
git commit -m "Implement versync check command"
```

---

### Task 15: CLI `init` command

**Files:**
- Modify: `lib/versync/cli.rb` (add `PROBES` and replace the `run_init` stub)
- Create: `test/fixtures/full_project_without_config/.ruby-version`, `Gemfile.lock`, `compose.yaml`
- Modify: `test/cli_test.rb`

- [ ] **Step 1: Write the failing test and fixture**

`test/fixtures/full_project_without_config/.ruby-version`, `Gemfile.lock`, `compose.yaml`: identical content to `test/fixtures/full_project/`'s same-named files, but with **no** `.versync.yml`.

Add to `test/cli_test.rb`:
```ruby
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
```

Add `require "yaml"` near the top of `test/cli_test.rb`.

- [ ] **Step 2: Run to verify failure** — stub always returns `1`.

- [ ] **Step 3: Implement**

In `lib/versync/cli.rb`, add near `COMMANDS`:
```ruby
    PROBES = [
      { "name" => "ruby", "check" => ->(root) { File.exist?(File.join(root, ".ruby-version")) },
        "config" => { "adapter" => "ruby_version" } },
      { "name" => "rails", "check" => ->(root) { File.exist?(File.join(root, "Gemfile.lock")) },
        "config" => { "adapter" => "bundler", "gem" => "rails" } },
      { "name" => "postgres", "check" => ->(root) { compose_file_present?(root) },
        "config" => { "adapter" => "docker_compose", "service" => "db" } },
      { "name" => "redis", "check" => ->(root) { compose_file_present?(root) },
        "config" => { "adapter" => "docker_compose", "service" => "redis" } }
    ].freeze

    def self.compose_file_present?(root)
      Adapters::DockerCompose::CANDIDATE_FILENAMES.any? { |filename| File.exist?(File.join(root, filename)) }
    end
```

Replace `run_init`:
```ruby
    def run_init
      if File.exist?(config_path)
        @stderr.puts ".versync.yml already exists"
        return 1
      end

      facts = PROBES.each_with_object({}) do |probe, acc|
        next unless probe["check"].call(project_root)

        acc[probe["name"]] = probe["config"]
      end

      File.write(config_path, YAML.dump("facts" => facts))
      @stdout.puts "Wrote #{config_path} with #{facts.size} detected fact(s)"
      0
    end
```

- [ ] **Step 4: Run to verify pass** — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/cli.rb test/cli_test.rb test/fixtures/full_project_without_config
git commit -m "Implement versync init command"
```

---

### Task 16: README, packaging check, and end-to-end smoke test

**Files:**
- Create: `README.md`
- Modify: `test/cli_test.rb`

- [ ] **Step 1: Write the end-to-end tests**

Add to `test/cli_test.rb`:
```ruby
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
```

- [ ] **Step 2: Run to verify pass** — Both examples should already PASS, since Tasks 12–15 implemented every command exercised. This is a regression check, not new-feature TDD — a failure here means an earlier task has a bug to fix before continuing.

- [ ] **Step 3: Write the README**

`README.md`:
````markdown
# versync

A lockfile tells you which *libraries* a project depends on. It says nothing
about the surrounding *services* — which PostgreSQL, Redis, or RabbitMQ
version the project actually runs against. That information tends to live
scattered across README files, AI-agent context docs, and Compose files,
copied by hand, drifting out of sync as the project evolves.

versync extracts version facts from your project's own repository state and
writes them to one canonical, always-regenerated `VERSIONS.md` and
`versync.json` — a single source of truth for humans and AI coding agents
alike.

## Install

```bash
bundle add versync --group development
```

## Usage

```bash
versync init    # detect available facts and write a starting .versync.yml
versync facts   # print current facts to the terminal
versync sync    # regenerate VERSIONS.md and versync.json
versync check   # exit non-zero if `sync` would change anything (for CI)
```

## Configuration

`.versync.yml` declares which facts to track:

```yaml
facts:
  ruby:
    adapter: ruby_version
  rails:
    adapter: bundler
    gem: rails
  postgres:
    adapter: docker_compose
    service: db
  redis:
    adapter: docker_compose
    service: redis
```

v0.1 ships three adapters: `ruby_version` (reads `.ruby-version`), `bundler`
(reads a named gem's version from `Gemfile.lock`), and `docker_compose`
(reads a named service's image tag from `compose.yaml`/`compose.yml`/
`docker-compose.yaml`/`docker-compose.yml`, whichever is found first).

A fact that can't be extracted (missing file, service, or tag) is omitted
from the output and reported as a warning, not guessed or silently dropped.

## What versync deliberately does not do

- It doesn't check whether a newer version is available upstream — that's
  what Renovate/Dependabot already do well.
- It doesn't parse arbitrary free-text docs looking for stale version
  mentions in v0.1 (see the design spec's roadmap for the planned opt-in
  marker syntax).

See `docs/superpowers/specs/2026-08-25-versync-design.md` for the full
design.

## License

MIT
````

Run: `gem build versync.gemspec` — expect success (delete the produced `.gem`, it's git-ignored and not committed).

- [ ] **Step 4: Run the full test suite one final time**

Run: `bundle exec rake test`
Expected: PASS (every test across all 16 tasks).

- [ ] **Step 5: Commit**

```bash
git add README.md test/cli_test.rb
git commit -m "Add README and end-to-end smoke tests"
```

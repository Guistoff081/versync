# versync v0.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a working `versync` Ruby gem that extracts Ruby/Rails/Docker-Compose version facts from a project's own repository state and generates a canonical `VERSIONS.md` + `versync.json`, with a `check` command suitable for CI.

**Architecture:** Small isolated adapters (one per fact source) feed a `FactsCollector`, which produces a plain list of `Fact` value objects. Two renderers turn that list into the canonical Markdown and JSON outputs. A `DiffChecker` compares freshly collected facts against the last-synced `versync.json` (ignoring timestamp/commit metadata) to answer "is this stale?". A hand-rolled `CLI` class wires configuration, collection, rendering, and diffing together behind four subcommands.

**Tech Stack:** Ruby (gem, no Rails dependency), RSpec for tests, no external runtime dependencies beyond the Ruby standard library (`yaml`, `json`, `time`).

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

- The spec's illustrated `VERSIONS.md` includes a `_Last synced: <timestamp>_` line. If `check` compared full rendered file bytes against disk, it would report "stale" on every run purely because the timestamp changed — even when no fact actually changed. To avoid this, `DiffChecker` compares **structured fact data** (name/value/source) parsed from the existing `versync.json`, not rendered file bytes, and ignores `generated_at`/`commit` differences. See Task 11.
- The spec's illustrated `VERSIONS.md` table capitalizes fact names for display ("Ruby", "Rails", "PostgreSQL"), but that display mapping isn't defined anywhere in the spec — the `.versync.yml` config keys that produce fact names are lowercase (`ruby`, `rails`, `postgres`). Rather than invent an undocumented capitalization/display-name table, the Markdown renderer (Task 10) prints the fact `name` exactly as configured. If the user wants title-cased output later, that's a config addition (e.g. a `label:` per fact), not something to guess at now.

---

### Task 1: Project scaffolding

**Files:**
- Create: `versync.gemspec`
- Create: `Gemfile`
- Create: `.gitignore`
- Create: `LICENSE.txt`
- Create: `lib/versync/version.rb`
- Create: `lib/versync.rb`
- Create: `.rspec`
- Create: `spec/spec_helper.rb`
- Create: `spec/versync_spec.rb`

**Interfaces:**
- Produces: `Versync::VERSION` (String constant). `with_temp_project(&block)` — yields a temp dir path, cleans it up after. `copy_fixture(fixture_name, project_root)` — copies `spec/fixtures/<fixture_name>/*` into `project_root`. Every later task's specs `require "spec_helper"` and use these two helpers.

- [ ] **Step 1: Create the gem skeleton files**

`versync.gemspec`:
```ruby
require_relative "lib/versync/version"

Gem::Specification.new do |spec|
  spec.name = "versync"
  spec.version = Versync::VERSION
  spec.authors = ["guigo"]
  spec.email = ["guigo@example.com"]
  spec.summary = "Keeps documented repository facts (Ruby, Rails, service versions) in sync with reality."
  spec.description = "versync extracts version facts from a Ruby/Rails project's own repository state " \
                      "and generates a canonical VERSIONS.md/versync.json that both humans and AI agents " \
                      "can treat as ground truth."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir["lib/**/*.rb", "exe/*", "LICENSE.txt", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["versync"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rspec", "~> 3.13"
end
```

`Gemfile`:
```ruby
source "https://rubygems.org"

gemspec
```

`.gitignore`:
```
/.bundle/
/Gemfile.lock
*.gem
.rspec_status
```

`LICENSE.txt`:
```
MIT License

Copyright (c) 2026 guigo

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

`.rspec`:
```
--require spec_helper
```

- [ ] **Step 2: Write the failing smoke test and spec helper**

`spec/spec_helper.rb`:
```ruby
require "versync"
require "tmpdir"
require "fileutils"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end

def with_temp_project
  Dir.mktmpdir do |dir|
    yield dir
  end
end

def copy_fixture(fixture_name, project_root)
  fixture_path = File.join(__dir__, "fixtures", fixture_name)
  FileUtils.cp_r(Dir.glob("#{fixture_path}/*"), project_root)
end
```

`spec/versync_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe Versync do
  it "has a version number" do
    expect(Versync::VERSION).not_to be_nil
  end
end
```

- [ ] **Step 3: Run the test suite to verify it fails**

Run: `bundle install && bundle exec rspec`
Expected: FAIL — `LoadError: cannot load such file -- versync` (neither `lib/versync.rb` nor `lib/versync/version.rb` exist yet).

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

Run: `bundle exec rspec`
Expected: PASS (1 example, 0 failures).

- [ ] **Step 6: Commit**

```bash
git add versync.gemspec Gemfile .gitignore LICENSE.txt lib .rspec spec
git commit -m "Scaffold versync gem with RSpec harness"
```

---

### Task 2: `Fact` value object and `Adapters::Base` interface

**Files:**
- Create: `lib/versync/fact.rb`
- Create: `lib/versync/adapters/base.rb`
- Modify: `lib/versync.rb`
- Test: `spec/fact_spec.rb`
- Test: `spec/adapters/base_spec.rb`

**Interfaces:**
- Consumes: nothing from earlier tasks beyond the gem skeleton.
- Produces: `Versync::Fact.new(name:, value:, source:)` (keyword-init Struct, comparable by value). `Versync::Adapters::Base` — abstract adapter with `#name`, `#available?(project_root)`, `#extract(project_root, options)`, all raising `NotImplementedError` by default. `Versync::Adapters::NotFoundError` — raised by concrete adapters when a fact cannot be extracted. Every adapter task (3, 4, 5) subclasses `Adapters::Base` and raises `Adapters::NotFoundError`; `FactsCollector` (Task 7) rescues `Adapters::NotFoundError`.

- [ ] **Step 1: Write the failing tests**

`spec/fact_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe Versync::Fact do
  it "is a value object comparable by name, value and source" do
    a = described_class.new(name: "ruby", value: "4.0.6", source: ".ruby-version")
    b = described_class.new(name: "ruby", value: "4.0.6", source: ".ruby-version")

    expect(a).to eq(b)
  end
end
```

`spec/adapters/base_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe Versync::Adapters::Base do
  subject(:adapter) { described_class.new }

  it "raises NotImplementedError for #name" do
    expect { adapter.name }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for #available?" do
    expect { adapter.available?("/some/root") }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for #extract" do
    expect { adapter.extract("/some/root", {}) }.to raise_error(NotImplementedError)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/fact_spec.rb spec/adapters/base_spec.rb`
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

Add to `lib/versync.rb` (after the existing `require_relative "versync/version"` line):
```ruby
require_relative "versync/fact"
require_relative "versync/adapters/base"
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec`
Expected: PASS (all examples so far).

- [ ] **Step 5: Commit**

```bash
git add lib/versync/fact.rb lib/versync/adapters/base.rb lib/versync.rb spec/fact_spec.rb spec/adapters/base_spec.rb
git commit -m "Add Fact value object and Adapters::Base interface"
```

---

### Task 3: `ruby_version` adapter

**Files:**
- Create: `lib/versync/adapters/ruby_version.rb`
- Create: `spec/fixtures/ruby_project/.ruby-version`
- Modify: `lib/versync.rb`
- Test: `spec/adapters/ruby_version_spec.rb`

**Interfaces:**
- Consumes: `Versync::Adapters::Base`, `Versync::Adapters::NotFoundError` (Task 2).
- Produces: `Versync::Adapters::RubyVersion.new.extract(project_root, options)` → `{ value: "4.0.6", source: ".ruby-version" }`. Registered under adapter name `"ruby_version"` in `FactsCollector`'s registry (Task 7).

- [ ] **Step 1: Write the failing test and fixture**

`spec/fixtures/ruby_project/.ruby-version`:
```
4.0.6
```

`spec/adapters/ruby_version_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe Versync::Adapters::RubyVersion do
  subject(:adapter) { described_class.new }

  it "is available when .ruby-version exists" do
    with_temp_project do |dir|
      copy_fixture("ruby_project", dir)
      expect(adapter.available?(dir)).to be true
    end
  end

  it "is not available when .ruby-version is missing" do
    with_temp_project do |dir|
      expect(adapter.available?(dir)).to be false
    end
  end

  it "extracts the ruby version, stripped of whitespace" do
    with_temp_project do |dir|
      copy_fixture("ruby_project", dir)
      result = adapter.extract(dir, {})
      expect(result).to eq(value: "4.0.6", source: ".ruby-version")
    end
  end

  it "raises NotFoundError when .ruby-version is missing" do
    with_temp_project do |dir|
      expect { adapter.extract(dir, {}) }.to raise_error(Versync::Adapters::NotFoundError)
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/adapters/ruby_version_spec.rb`
Expected: FAIL — `uninitialized constant Versync::Adapters::RubyVersion`.

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

Add to `lib/versync.rb`:
```ruby
require_relative "versync/adapters/ruby_version"
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/adapters/ruby_version.rb lib/versync.rb spec/adapters/ruby_version_spec.rb spec/fixtures/ruby_project
git commit -m "Add ruby_version adapter"
```

---

### Task 4: `bundler` adapter

**Files:**
- Create: `lib/versync/adapters/bundler.rb`
- Create: `spec/fixtures/bundler_project/Gemfile.lock`
- Modify: `lib/versync.rb`
- Test: `spec/adapters/bundler_spec.rb`

**Interfaces:**
- Consumes: `Versync::Adapters::Base`, `Versync::Adapters::NotFoundError` (Task 2).
- Produces: `Versync::Adapters::Bundler.new.extract(project_root, { "gem" => "rails" })` → `{ value: "8.1.3", source: "Gemfile.lock" }`. Registered under adapter name `"bundler"` in `FactsCollector`'s registry (Task 7).

- [ ] **Step 1: Write the failing test and fixture**

`spec/fixtures/bundler_project/Gemfile.lock`:
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

`spec/adapters/bundler_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe Versync::Adapters::Bundler do
  subject(:adapter) { described_class.new }

  around do |example|
    with_temp_project do |dir|
      copy_fixture("bundler_project", dir)
      @project_root = dir
      example.run
    end
  end

  it "is available when Gemfile.lock exists" do
    expect(adapter.available?(@project_root)).to be true
  end

  it "extracts the version of the named top-level gem" do
    result = adapter.extract(@project_root, { "gem" => "rails" })
    expect(result).to eq(value: "8.1.3", source: "Gemfile.lock")
  end

  it "does not match nested dependency version constraints" do
    result = adapter.extract(@project_root, { "gem" => "concurrent-ruby" })
    expect(result).to eq(value: "1.2.2", source: "Gemfile.lock")
  end

  it "raises NotFoundError when the gem is not in the lockfile" do
    expect { adapter.extract(@project_root, { "gem" => "sidekiq" }) }
      .to raise_error(Versync::Adapters::NotFoundError)
  end

  it "raises NotFoundError when no 'gem' option is given" do
    expect { adapter.extract(@project_root, {}) }
      .to raise_error(Versync::Adapters::NotFoundError)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/adapters/bundler_spec.rb`
Expected: FAIL — `uninitialized constant Versync::Adapters::Bundler`.

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

Add to `lib/versync.rb`:
```ruby
require_relative "versync/adapters/bundler"
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/adapters/bundler.rb lib/versync.rb spec/adapters/bundler_spec.rb spec/fixtures/bundler_project
git commit -m "Add bundler adapter"
```

---

### Task 5: `docker_compose` adapter

**Files:**
- Create: `lib/versync/adapters/docker_compose.rb`
- Create: `spec/fixtures/docker_compose_project/docker-compose.yml`
- Modify: `lib/versync.rb`
- Test: `spec/adapters/docker_compose_spec.rb`

**Interfaces:**
- Consumes: `Versync::Adapters::Base`, `Versync::Adapters::NotFoundError` (Task 2).
- Produces: `Versync::Adapters::DockerCompose.new.extract(project_root, { "service" => "db" })` → `{ value: "18.1-alpine", source: "docker-compose.yml (db)" }`. Registered under adapter name `"docker_compose"` in `FactsCollector`'s registry (Task 7).

- [ ] **Step 1: Write the failing test and fixture**

`spec/fixtures/docker_compose_project/docker-compose.yml`:
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

`spec/adapters/docker_compose_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe Versync::Adapters::DockerCompose do
  subject(:adapter) { described_class.new }

  around do |example|
    with_temp_project do |dir|
      copy_fixture("docker_compose_project", dir)
      @project_root = dir
      example.run
    end
  end

  it "is available when docker-compose.yml exists" do
    expect(adapter.available?(@project_root)).to be true
  end

  it "extracts the image tag for a service" do
    result = adapter.extract(@project_root, { "service" => "db" })
    expect(result).to eq(value: "18.1-alpine", source: "docker-compose.yml (db)")
  end

  it "raises NotFoundError when the service has no tag" do
    expect { adapter.extract(@project_root, { "service" => "no_tag" }) }
      .to raise_error(Versync::Adapters::NotFoundError)
  end

  it "raises NotFoundError when the service has no image key" do
    expect { adapter.extract(@project_root, { "service" => "built" }) }
      .to raise_error(Versync::Adapters::NotFoundError)
  end

  it "raises NotFoundError when the service does not exist" do
    expect { adapter.extract(@project_root, { "service" => "missing" }) }
      .to raise_error(Versync::Adapters::NotFoundError)
  end

  it "raises NotFoundError when no 'service' option is given" do
    expect { adapter.extract(@project_root, {}) }
      .to raise_error(Versync::Adapters::NotFoundError)
  end

  it "raises NotFoundError for a registry host:port image with no tag" do
    expect { adapter.extract(@project_root, { "service" => "registry_no_tag" }) }
      .to raise_error(Versync::Adapters::NotFoundError)
  end

  it "extracts the tag for a registry host:port image with a tag" do
    result = adapter.extract(@project_root, { "service" => "registry_tag" })
    expect(result).to eq(value: "18", source: "docker-compose.yml (registry_tag)")
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/adapters/docker_compose_spec.rb`
Expected: FAIL — `uninitialized constant Versync::Adapters::DockerCompose`.

- [ ] **Step 3: Implement**

`lib/versync/adapters/docker_compose.rb`:
```ruby
require "yaml"

module Versync
  module Adapters
    class DockerCompose < Base
      def name
        "docker_compose"
      end

      def available?(project_root)
        File.exist?(compose_path(project_root))
      end

      def extract(project_root, options)
        service_name = options["service"]
        raise NotFoundError, "docker_compose adapter requires a 'service' option" unless service_name

        path = compose_path(project_root)
        raise NotFoundError, "docker-compose.yml not found" unless File.exist?(path)

        compose = YAML.safe_load(File.read(path)) || {}
        service = compose.dig("services", service_name)
        raise NotFoundError, "service '#{service_name}' not found in docker-compose.yml" unless service

        image = service["image"]
        raise NotFoundError, "service '#{service_name}' has no 'image' key" unless image

        tag = extract_tag(image)
        raise NotFoundError, "service '#{service_name}' image '#{image}' has no tag" unless tag

        { value: tag, source: "docker-compose.yml (#{service_name})" }
      end

      private

      def compose_path(project_root)
        File.join(project_root, "docker-compose.yml")
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

Add to `lib/versync.rb`:
```ruby
require_relative "versync/adapters/docker_compose"
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/adapters/docker_compose.rb lib/versync.rb spec/adapters/docker_compose_spec.rb spec/fixtures/docker_compose_project
git commit -m "Add docker_compose adapter"
```

---

### Task 6: `Configuration`

**Files:**
- Create: `lib/versync/configuration.rb`
- Create: `spec/fixtures/config_project/.versync.yml`
- Modify: `lib/versync.rb`
- Test: `spec/configuration_spec.rb`

**Interfaces:**
- Consumes: nothing from earlier tasks (standalone YAML parsing).
- Produces: `Versync::Configuration.load(path)` → `Versync::Configuration` instance with `#markdown_output` (String), `#json_output` (String), `#fact_configs` (Array of `Versync::Configuration::FactConfig`, a keyword-init Struct with `:name, :adapter, :options`). Raises `Errno::ENOENT` if `path` doesn't exist. `FactsCollector` (Task 7) consumes `#fact_configs`; the CLI (Task 12+) consumes `#markdown_output`/`#json_output`.

- [ ] **Step 1: Write the failing test and fixture**

`spec/fixtures/config_project/.versync.yml`:
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

`spec/configuration_spec.rb`:
```ruby
require "spec_helper"
require "yaml"

RSpec.describe Versync::Configuration do
  describe ".load" do
    it "parses output paths and fact configs from .versync.yml" do
      with_temp_project do |dir|
        copy_fixture("config_project", dir)
        config = described_class.load(File.join(dir, ".versync.yml"))

        expect(config.markdown_output).to eq("VERSIONS.md")
        expect(config.json_output).to eq("versync.json")
        expect(config.fact_configs).to contain_exactly(
          Versync::Configuration::FactConfig.new(name: "ruby", adapter: "ruby_version", options: {}),
          Versync::Configuration::FactConfig.new(name: "rails", adapter: "bundler", options: { "gem" => "rails" }),
          Versync::Configuration::FactConfig.new(name: "postgres", adapter: "docker_compose", options: { "service" => "db" })
        )
      end
    end

    it "defaults output paths when 'output' is not present" do
      with_temp_project do |dir|
        File.write(File.join(dir, ".versync.yml"), YAML.dump("facts" => {}))
        config = described_class.load(File.join(dir, ".versync.yml"))

        expect(config.markdown_output).to eq("VERSIONS.md")
        expect(config.json_output).to eq("versync.json")
      end
    end

    it "raises Errno::ENOENT when the file does not exist" do
      with_temp_project do |dir|
        expect { described_class.load(File.join(dir, ".versync.yml")) }.to raise_error(Errno::ENOENT)
      end
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/configuration_spec.rb`
Expected: FAIL — `uninitialized constant Versync::Configuration`.

- [ ] **Step 3: Implement**

`lib/versync/configuration.rb`:
```ruby
require "yaml"

module Versync
  class Configuration
    FactConfig = Struct.new(:name, :adapter, :options, keyword_init: true)

    DEFAULT_MARKDOWN_OUTPUT = "VERSIONS.md"
    DEFAULT_JSON_OUTPUT = "versync.json"

    attr_reader :markdown_output, :json_output, :fact_configs

    def self.load(path)
      raise Errno::ENOENT, path unless File.exist?(path)

      data = YAML.safe_load(File.read(path)) || {}
      new(data)
    end

    def initialize(data)
      output = data.fetch("output", {}) || {}
      @markdown_output = output.fetch("markdown", DEFAULT_MARKDOWN_OUTPUT)
      @json_output = output.fetch("json", DEFAULT_JSON_OUTPUT)

      @fact_configs = (data.fetch("facts", {}) || {}).map do |fact_name, fact_data|
        options = fact_data.reject { |key, _| key == "adapter" }
        FactConfig.new(name: fact_name, adapter: fact_data.fetch("adapter"), options: options)
      end
    end
  end
end
```

Add to `lib/versync.rb`:
```ruby
require_relative "versync/configuration"
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/configuration.rb lib/versync.rb spec/configuration_spec.rb spec/fixtures/config_project
git commit -m "Add Configuration for .versync.yml"
```

---

### Task 7: `FactsCollector`

**Files:**
- Create: `lib/versync/facts_collector.rb`
- Modify: `lib/versync.rb`
- Test: `spec/facts_collector_spec.rb`

**Interfaces:**
- Consumes: `Versync::Adapters::Base`, `Versync::Adapters::NotFoundError` (Task 2); `Versync::Configuration::FactConfig` (Task 6); `Versync::Fact` (Task 2); the three concrete adapters (Tasks 3–5) for the default registry.
- Produces: `Versync::FactsCollector.new(adapter_registry: ...).collect(project_root, fact_configs)` → `Array<Versync::Fact>`. `Versync::FactsCollector::UnknownAdapterError`. The default registry (used when `adapter_registry:` is omitted) maps `"ruby_version"`, `"bundler"`, `"docker_compose"` to the Task 3–5 adapters — the CLI (Task 12+) relies on this default. Consumed by the CLI's `run_facts`/`run_sync`/`run_check`.

- [ ] **Step 1: Write the failing test**

`spec/facts_collector_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe Versync::FactsCollector do
  let(:success_adapter) do
    Class.new(Versync::Adapters::Base) do
      def extract(project_root, options)
        { value: "1.2.3", source: "fake" }
      end
    end.new
  end

  let(:not_found_adapter) do
    Class.new(Versync::Adapters::Base) do
      def extract(project_root, options)
        raise Versync::Adapters::NotFoundError, "nope"
      end
    end.new
  end

  let(:registry) do
    { "fake_success" => -> { success_adapter }, "fake_not_found" => -> { not_found_adapter } }
  end

  subject(:collector) { described_class.new(adapter_registry: registry) }

  it "collects facts from adapters that succeed" do
    configs = [Versync::Configuration::FactConfig.new(name: "ruby", adapter: "fake_success", options: {})]

    facts = collector.collect("/fake/root", configs)

    expect(facts).to contain_exactly(Versync::Fact.new(name: "ruby", value: "1.2.3", source: "fake"))
  end

  it "skips facts whose adapter raises NotFoundError" do
    configs = [Versync::Configuration::FactConfig.new(name: "missing", adapter: "fake_not_found", options: {})]

    facts = collector.collect("/fake/root", configs)

    expect(facts).to be_empty
  end

  it "raises UnknownAdapterError for an unregistered adapter name" do
    configs = [Versync::Configuration::FactConfig.new(name: "x", adapter: "nope", options: {})]

    expect { collector.collect("/fake/root", configs) }
      .to raise_error(Versync::FactsCollector::UnknownAdapterError)
  end

  it "defaults to a registry covering ruby_version, bundler and docker_compose" do
    default_collector = described_class.new
    configs = [Versync::Configuration::FactConfig.new(name: "ruby", adapter: "ruby_version", options: {})]

    with_temp_project do |dir|
      copy_fixture("ruby_project", dir)
      facts = default_collector.collect(dir, configs)
      expect(facts).to contain_exactly(Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version"))
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/facts_collector_spec.rb`
Expected: FAIL — `uninitialized constant Versync::FactsCollector`.

- [ ] **Step 3: Implement**

`lib/versync/facts_collector.rb`:
```ruby
module Versync
  class FactsCollector
    class UnknownAdapterError < StandardError; end

    DEFAULT_ADAPTER_REGISTRY = {
      "ruby_version" => -> { Adapters::RubyVersion.new },
      "bundler" => -> { Adapters::Bundler.new },
      "docker_compose" => -> { Adapters::DockerCompose.new }
    }.freeze

    def initialize(adapter_registry: DEFAULT_ADAPTER_REGISTRY)
      @adapter_registry = adapter_registry
    end

    # Returns an Array of Fact. Fact configs whose adapter raises
    # Adapters::NotFoundError are silently skipped rather than failing
    # the whole run.
    def collect(project_root, fact_configs)
      fact_configs.filter_map do |fact_config|
        adapter = build_adapter(fact_config.adapter)
        begin
          result = adapter.extract(project_root, fact_config.options)
          Fact.new(name: fact_config.name, value: result.fetch(:value), source: result.fetch(:source))
        rescue Adapters::NotFoundError
          nil
        end
      end
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

Add to `lib/versync.rb`:
```ruby
require_relative "versync/facts_collector"
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/facts_collector.rb lib/versync.rb spec/facts_collector_spec.rb
git commit -m "Add FactsCollector orchestrating adapters"
```

---

### Task 8: `GitInfo`

**Files:**
- Create: `lib/versync/git_info.rb`
- Modify: `lib/versync.rb`
- Test: `spec/git_info_spec.rb`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `Versync::GitInfo.current_sha(project_root)` → 40-character SHA String, or `nil` if `project_root` isn't a git repository (or has no commits). Consumed by the CLI's `run_sync` (Task 13) to populate the `commit:` metadata passed to both renderers.

- [ ] **Step 1: Write the failing test**

`spec/git_info_spec.rb`:
```ruby
require "spec_helper"

RSpec.describe Versync::GitInfo do
  describe ".current_sha" do
    it "returns the current HEAD commit sha for a git repository" do
      with_temp_project do |dir|
        Dir.chdir(dir) do
          system("git init -q")
          system("git config user.email test@example.com")
          system("git config user.name Test")
          File.write("file.txt", "content")
          system("git add file.txt")
          system("git commit -q -m initial")
        end

        sha = Versync::GitInfo.current_sha(dir)

        expect(sha).to match(/\A[0-9a-f]{40}\z/)
      end
    end

    it "returns nil when the directory is not a git repository" do
      with_temp_project do |dir|
        expect(Versync::GitInfo.current_sha(dir)).to be_nil
      end
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/git_info_spec.rb`
Expected: FAIL — `uninitialized constant Versync::GitInfo`.

- [ ] **Step 3: Implement**

`lib/versync/git_info.rb`:
```ruby
module Versync
  module GitInfo
    def self.current_sha(project_root)
      sha = Dir.chdir(project_root) { `git rev-parse HEAD 2>/dev/null`.strip }
      sha.empty? ? nil : sha
    end
  end
end
```

Add to `lib/versync.rb`:
```ruby
require_relative "versync/git_info"
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/git_info.rb lib/versync.rb spec/git_info_spec.rb
git commit -m "Add GitInfo.current_sha"
```

---

### Task 9: `Renderers::Json`

**Files:**
- Create: `lib/versync/renderers/json.rb`
- Modify: `lib/versync.rb`
- Test: `spec/renderers/json_spec.rb`

**Interfaces:**
- Consumes: `Versync::Fact` (Task 2).
- Produces: `Versync::Renderers::Json.new(facts:, generated_at:, commit:).render` → JSON String with top-level keys `"generated_at"` (ISO 8601), `"commit"` (String or `null`), `"facts"` (Array of `{"name", "value", "source"}`). Consumed by the CLI's `run_sync` (Task 13) and by `DiffChecker` (Task 11), which parses this exact shape back out of `versync.json`.

- [ ] **Step 1: Write the failing test**

`spec/renderers/json_spec.rb`:
```ruby
require "spec_helper"
require "json"
require "time"

RSpec.describe Versync::Renderers::Json do
  it "renders facts, generated_at and commit as JSON" do
    facts = [Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version")]
    generated_at = Time.parse("2026-08-25T12:00:00Z")

    output = described_class.new(facts: facts, generated_at: generated_at, commit: "abc123").render
    parsed = JSON.parse(output)

    expect(parsed).to eq(
      "generated_at" => "2026-08-25T12:00:00Z",
      "commit" => "abc123",
      "facts" => [{ "name" => "ruby", "value" => "4.0.6", "source" => ".ruby-version" }]
    )
  end

  it "renders a null commit when none is given" do
    output = described_class.new(facts: [], generated_at: Time.parse("2026-08-25T12:00:00Z"), commit: nil).render

    expect(JSON.parse(output)["commit"]).to be_nil
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/renderers/json_spec.rb`
Expected: FAIL — `uninitialized constant Versync::Renderers`.

- [ ] **Step 3: Implement**

`lib/versync/renderers/json.rb`:
```ruby
require "json"

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

Add to `lib/versync.rb`:
```ruby
require_relative "versync/renderers/json"
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/renderers/json.rb lib/versync.rb spec/renderers/json_spec.rb
git commit -m "Add JSON renderer"
```

---

### Task 10: `Renderers::Markdown`

**Files:**
- Create: `lib/versync/renderers/markdown.rb`
- Modify: `lib/versync.rb`
- Test: `spec/renderers/markdown_spec.rb`

**Interfaces:**
- Consumes: `Versync::Fact` (Task 2).
- Produces: `Versync::Renderers::Markdown.new(facts:, generated_at:, commit:).render` → Markdown String (see spec's canonical output template). Consumed by the CLI's `run_sync` (Task 13).

- [ ] **Step 1: Write the failing test**

`spec/renderers/markdown_spec.rb`:
```ruby
require "spec_helper"
require "time"

RSpec.describe Versync::Renderers::Markdown do
  it "renders a facts table with header and footer" do
    facts = [
      Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version"),
      Versync::Fact.new(name: "rails", value: "8.1.3", source: "Gemfile.lock")
    ]
    generated_at = Time.parse("2026-08-25T12:00:00Z")

    output = described_class.new(facts: facts, generated_at: generated_at, commit: "abc123").render

    expect(output).to include("<!-- Generated by versync. Do not edit by hand — run `versync sync`. -->")
    expect(output).to include("| Fact | Version | Source |")
    expect(output).to include("| ruby | 4.0.6 | .ruby-version |")
    expect(output).to include("| rails | 8.1.3 | Gemfile.lock |")
    expect(output).to include("_Last synced: 2026-08-25T12:00:00Z · commit abc123_")
  end

  it "renders 'unknown' when commit is nil" do
    output = described_class.new(facts: [], generated_at: Time.parse("2026-08-25T12:00:00Z"), commit: nil).render

    expect(output).to include("commit unknown")
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/renderers/markdown_spec.rb`
Expected: FAIL — `uninitialized constant Versync::Renderers::Markdown`.

- [ ] **Step 3: Implement**

`lib/versync/renderers/markdown.rb`:
```ruby
module Versync
  module Renderers
    class Markdown
      def initialize(facts:, generated_at:, commit:)
        @facts = facts
        @generated_at = generated_at
        @commit = commit
      end

      def render
        rows = @facts.map { |fact| "| #{fact.name} | #{fact.value} | #{fact.source} |" }.join("\n")

        <<~MD
          <!-- Generated by versync. Do not edit by hand — run `versync sync`. -->

          # Repository Facts

          | Fact | Version | Source |
          |---|---|---|
          #{rows}

          _Last synced: #{@generated_at.utc.iso8601} · commit #{@commit || "unknown"}_
        MD
      end
    end
  end
end
```

Add to `lib/versync.rb`:
```ruby
require_relative "versync/renderers/markdown"
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/renderers/markdown.rb lib/versync.rb spec/renderers/markdown_spec.rb
git commit -m "Add Markdown renderer"
```

---

### Task 11: `DiffChecker`

**Files:**
- Create: `lib/versync/diff_checker.rb`
- Modify: `lib/versync.rb`
- Test: `spec/diff_checker_spec.rb`

**Interfaces:**
- Consumes: `Versync::Fact` (Task 2). Reads a `versync.json` file matching the exact shape produced by `Versync::Renderers::Json` (Task 9): top-level `"facts"` array of `{"name", "value", "source"}`.
- Produces: `Versync::DiffChecker.new(project_root:, json_output:).check(current_facts)` → `Versync::DiffChecker::Result` (keyword-init Struct: `stale?` Boolean, `missing_output` Boolean, `fact_diffs` Array of `{name:, before:, after:}` Hashes). Consumed by the CLI's `run_check` (Task 14). See "Design Decision Not Explicit In The Spec" above for why this compares structured facts rather than rendered file bytes.

- [ ] **Step 1: Write the failing test**

`spec/diff_checker_spec.rb`:
```ruby
require "spec_helper"
require "json"

RSpec.describe Versync::DiffChecker do
  it "reports stale when the json output file does not exist" do
    with_temp_project do |dir|
      checker = described_class.new(project_root: dir, json_output: "versync.json")
      result = checker.check([Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version")])

      expect(result.stale?).to be true
      expect(result.missing_output).to be true
    end
  end

  it "reports not stale when on-disk facts match current facts" do
    with_temp_project do |dir|
      File.write(File.join(dir, "versync.json"), JSON.generate(
        "generated_at" => "2026-08-25T12:00:00Z",
        "commit" => "abc123",
        "facts" => [{ "name" => "ruby", "value" => "4.0.6", "source" => ".ruby-version" }]
      ))

      checker = described_class.new(project_root: dir, json_output: "versync.json")
      result = checker.check([Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version")])

      expect(result.stale?).to be false
    end
  end

  it "ignores generated_at/commit differences and only compares facts" do
    with_temp_project do |dir|
      File.write(File.join(dir, "versync.json"), JSON.generate(
        "generated_at" => "2026-08-25T09:00:00Z",
        "commit" => "old-sha",
        "facts" => [{ "name" => "ruby", "value" => "4.0.6", "source" => ".ruby-version" }]
      ))

      checker = described_class.new(project_root: dir, json_output: "versync.json")
      result = checker.check([Versync::Fact.new(name: "ruby", value: "4.0.6", source: ".ruby-version")])

      expect(result.stale?).to be false
    end
  end

  it "reports a fact diff when a value changed" do
    with_temp_project do |dir|
      File.write(File.join(dir, "versync.json"), JSON.generate(
        "generated_at" => "2026-08-25T12:00:00Z",
        "commit" => "abc123",
        "facts" => [{ "name" => "rails", "value" => "8.0.2", "source" => "Gemfile.lock" }]
      ))

      checker = described_class.new(project_root: dir, json_output: "versync.json")
      result = checker.check([Versync::Fact.new(name: "rails", value: "8.1.3", source: "Gemfile.lock")])

      expect(result.stale?).to be true
      expect(result.fact_diffs).to contain_exactly(name: "rails", before: "8.0.2", after: "8.1.3")
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/diff_checker_spec.rb`
Expected: FAIL — `uninitialized constant Versync::DiffChecker`.

- [ ] **Step 3: Implement**

`lib/versync/diff_checker.rb`:
```ruby
require "json"

module Versync
  class DiffChecker
    Result = Struct.new(:stale?, :missing_output, :fact_diffs, keyword_init: true)

    def initialize(project_root:, json_output:)
      @project_root = project_root
      @json_output = json_output
    end

    def check(current_facts)
      path = File.join(@project_root, @json_output)
      return Result.new(stale?: true, missing_output: true, fact_diffs: []) unless File.exist?(path)

      on_disk = JSON.parse(File.read(path))
      on_disk_facts = on_disk.fetch("facts", []).map do |f|
        Fact.new(name: f["name"], value: f["value"], source: f["source"])
      end

      fact_diffs = diff_facts(on_disk_facts, current_facts)
      Result.new(stale?: !fact_diffs.empty?, missing_output: false, fact_diffs: fact_diffs)
    end

    private

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

Add to `lib/versync.rb`:
```ruby
require_relative "versync/diff_checker"
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/diff_checker.rb lib/versync.rb spec/diff_checker_spec.rb
git commit -m "Add DiffChecker comparing structured facts, not rendered bytes"
```

---

### Task 12: CLI skeleton, `exe/versync`, and `facts` command

**Files:**
- Create: `lib/versync/cli.rb`
- Create: `exe/versync`
- Create: `spec/fixtures/full_project/.ruby-version`
- Create: `spec/fixtures/full_project/Gemfile.lock`
- Create: `spec/fixtures/full_project/docker-compose.yml`
- Create: `spec/fixtures/full_project/.versync.yml`
- Modify: `lib/versync.rb`
- Test: `spec/cli_spec.rb`

**Interfaces:**
- Consumes: `Versync::Configuration` (Task 6), `Versync::FactsCollector` (Task 7).
- Produces: `Versync::CLI.new(argv, project_root: Dir.pwd, stdout: $stdout, stderr: $stderr).run` → Integer exit code. `run` dispatches on `argv.first` to one of `init`/`facts`/`sync`/`check`; unrecognized commands print usage to `stderr` and return `1`. This task implements `facts` for real; `sync`, `check`, `init` are stubs returning `1` here and get implemented in Tasks 13–15 by replacing those stub methods — later tasks do not change this class's public interface.

- [ ] **Step 1: Write the failing test and fixtures**

`spec/fixtures/full_project/.ruby-version`:
```
4.0.6
```

`spec/fixtures/full_project/Gemfile.lock`:
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

`spec/fixtures/full_project/docker-compose.yml`:
```yaml
services:
  db:
    image: postgres:18.1-alpine
  redis:
    image: redis:8.2
```

`spec/fixtures/full_project/.versync.yml`:
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

`spec/cli_spec.rb`:
```ruby
require "spec_helper"
require "stringio"

RSpec.describe Versync::CLI do
  describe "facts command" do
    it "prints each fact to stdout and returns 0" do
      with_temp_project do |dir|
        copy_fixture("full_project", dir)
        stdout = StringIO.new
        stderr = StringIO.new

        status = described_class.new(["facts"], project_root: dir, stdout: stdout, stderr: stderr).run

        expect(status).to eq(0)
        expect(stdout.string).to include("ruby: 4.0.6 (.ruby-version)")
        expect(stdout.string).to include("rails: 8.1.3 (Gemfile.lock)")
      end
    end

    it "returns 1 and prints an error when .versync.yml is missing" do
      with_temp_project do |dir|
        stdout = StringIO.new
        stderr = StringIO.new

        status = described_class.new(["facts"], project_root: dir, stdout: stdout, stderr: stderr).run

        expect(status).to eq(1)
        expect(stderr.string).to include(".versync.yml not found")
      end
    end
  end

  describe "unknown command" do
    it "returns 1 and prints usage" do
      stdout = StringIO.new
      stderr = StringIO.new

      status = described_class.new(["bogus"], stdout: stdout, stderr: stderr).run

      expect(status).to eq(1)
      expect(stderr.string).to include("Usage:")
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/cli_spec.rb`
Expected: FAIL — `uninitialized constant Versync::CLI`.

- [ ] **Step 3: Implement**

`lib/versync/cli.rb`:
```ruby
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

    def load_config
      Configuration.load(config_path)
    end

    def collect_facts(config)
      FactsCollector.new.collect(project_root, config.fact_configs)
    end

    def run_facts
      config = load_config
      collect_facts(config).each { |fact| @stdout.puts "#{fact.name}: #{fact.value} (#{fact.source})" }
      0
    rescue Errno::ENOENT
      @stderr.puts ".versync.yml not found — run `versync init` first"
      1
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

require_relative "../lib/versync"

exit Versync::CLI.new(ARGV).run
```

Make it executable: `chmod +x exe/versync`

Add to `lib/versync.rb`:
```ruby
require_relative "versync/cli"
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/cli.rb exe/versync lib/versync.rb spec/cli_spec.rb spec/fixtures/full_project
git commit -m "Add CLI skeleton, exe/versync, and facts command"
```

---

### Task 13: CLI `sync` command

**Files:**
- Modify: `lib/versync/cli.rb` (replace the `run_sync` stub)
- Modify: `spec/cli_spec.rb` (add a `sync command` describe block)

**Interfaces:**
- Consumes: `Versync::GitInfo.current_sha` (Task 8), `Versync::Renderers::Markdown`/`Json` (Tasks 9–10), `config.markdown_output`/`config.json_output` (Task 6).
- Produces: writes `<project_root>/<config.markdown_output>` and `<project_root>/<config.json_output>`. No new public interface beyond what Task 12 already declared.

- [ ] **Step 1: Write the failing test**

Add to `spec/cli_spec.rb` (inside the top-level `RSpec.describe Versync::CLI do ... end`, alongside the existing `describe` blocks):
```ruby
  describe "sync command" do
    it "writes VERSIONS.md and versync.json from current facts" do
      with_temp_project do |dir|
        copy_fixture("full_project", dir)

        status = described_class.new(["sync"], project_root: dir, stdout: StringIO.new, stderr: StringIO.new).run

        expect(status).to eq(0)
        markdown = File.read(File.join(dir, "VERSIONS.md"))
        json = JSON.parse(File.read(File.join(dir, "versync.json")))

        expect(markdown).to include("| ruby | 4.0.6 | .ruby-version |")
        expect(json["facts"]).to include("name" => "ruby", "value" => "4.0.6", "source" => ".ruby-version")
      end
    end

    it "returns 1 and prints an error when .versync.yml is missing" do
      with_temp_project do |dir|
        stderr = StringIO.new

        status = described_class.new(["sync"], project_root: dir, stdout: StringIO.new, stderr: stderr).run

        expect(status).to eq(1)
        expect(stderr.string).to include(".versync.yml not found")
      end
    end
  end
```

Add `require "json"` near the top of `spec/cli_spec.rb`, alongside the existing `require "stringio"`.

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/cli_spec.rb -e "sync command"`
Expected: FAIL — `status` is `1` instead of `0` (stub always returns `1`), no `VERSIONS.md` written.

- [ ] **Step 3: Implement**

In `lib/versync/cli.rb`, replace:
```ruby
    def run_sync
      1
    end
```
with:
```ruby
    def run_sync
      config = load_config
      facts = collect_facts(config)
      generated_at = Time.now
      commit = GitInfo.current_sha(project_root)

      markdown = Renderers::Markdown.new(facts: facts, generated_at: generated_at, commit: commit).render
      json = Renderers::Json.new(facts: facts, generated_at: generated_at, commit: commit).render

      File.write(File.join(project_root, config.markdown_output), markdown)
      File.write(File.join(project_root, config.json_output), json)

      @stdout.puts "Synced #{facts.size} fact(s) to #{config.markdown_output} and #{config.json_output}"
      0
    rescue Errno::ENOENT
      @stderr.puts ".versync.yml not found — run `versync init` first"
      1
    end
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/cli.rb spec/cli_spec.rb
git commit -m "Implement versync sync command"
```

---

### Task 14: CLI `check` command

**Files:**
- Modify: `lib/versync/cli.rb` (replace the `run_check` stub)
- Modify: `spec/cli_spec.rb` (add a `check command` describe block)

**Interfaces:**
- Consumes: `Versync::DiffChecker` (Task 11), `config.json_output` (Task 6).
- Produces: no new public interface beyond Task 12; exit code `1` with a diagnostic on `stderr` when stale, `0` with a confirmation on `stdout` when not.

- [ ] **Step 1: Write the failing test**

Add to `spec/cli_spec.rb`:
```ruby
  describe "check command" do
    it "returns 1 when versync.json does not exist yet" do
      with_temp_project do |dir|
        copy_fixture("full_project", dir)
        stderr = StringIO.new

        status = described_class.new(["check"], project_root: dir, stdout: StringIO.new, stderr: stderr).run

        expect(status).to eq(1)
        expect(stderr.string).to include("versync is stale")
      end
    end

    it "returns 0 after a sync has been run" do
      with_temp_project do |dir|
        copy_fixture("full_project", dir)
        described_class.new(["sync"], project_root: dir, stdout: StringIO.new, stderr: StringIO.new).run

        status = described_class.new(["check"], project_root: dir, stdout: StringIO.new, stderr: StringIO.new).run

        expect(status).to eq(0)
      end
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/cli_spec.rb -e "check command"`
Expected: FAIL — `status` is `1` in both cases (stub always returns `1`), so the "returns 0 after a sync" example fails.

- [ ] **Step 3: Implement**

In `lib/versync/cli.rb`, replace:
```ruby
    def run_check
      1
    end
```
with:
```ruby
    def run_check
      config = load_config
      facts = collect_facts(config)
      result = DiffChecker.new(project_root: project_root, json_output: config.json_output).check(facts)

      if result.stale?
        @stderr.puts "versync is stale — run `versync sync`:"
        if result.missing_output
          @stderr.puts "  #{config.json_output} does not exist"
        else
          result.fact_diffs.each do |diff|
            @stderr.puts "  #{diff[:name]}: documented=#{diff[:before].inspect} actual=#{diff[:after].inspect}"
          end
        end
        return 1
      end

      @stdout.puts "versync is up to date"
      0
    rescue Errno::ENOENT
      @stderr.puts ".versync.yml not found — run `versync init` first"
      1
    end
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/cli.rb spec/cli_spec.rb
git commit -m "Implement versync check command"
```

---

### Task 15: CLI `init` command

**Files:**
- Modify: `lib/versync/cli.rb` (add the `PROBES` constant and replace the `run_init` stub)
- Create: `spec/fixtures/full_project_without_config/.ruby-version`
- Create: `spec/fixtures/full_project_without_config/Gemfile.lock`
- Create: `spec/fixtures/full_project_without_config/docker-compose.yml`
- Modify: `spec/cli_spec.rb` (add an `init command` describe block)

**Interfaces:**
- Consumes: nothing new from earlier tasks (file-presence probing only).
- Produces: writes `<project_root>/.versync.yml`. No new public interface beyond Task 12.

- [ ] **Step 1: Write the failing test and fixture**

`spec/fixtures/full_project_without_config/.ruby-version`, `Gemfile.lock`, `docker-compose.yml`: identical content to the same-named files in `spec/fixtures/full_project/` (copy them), but with **no** `.versync.yml`.

Add to `spec/cli_spec.rb`:
```ruby
  describe "init command" do
    it "writes .versync.yml with detected facts based on file presence" do
      with_temp_project do |dir|
        copy_fixture("full_project_without_config", dir)

        status = described_class.new(["init"], project_root: dir, stdout: StringIO.new, stderr: StringIO.new).run

        expect(status).to eq(0)
        config = YAML.safe_load(File.read(File.join(dir, ".versync.yml")))

        expect(config["facts"].keys).to contain_exactly("ruby", "rails", "postgres", "redis")
        expect(config["facts"]["rails"]).to eq("adapter" => "bundler", "gem" => "rails")
      end
    end

    it "returns 1 without overwriting an existing .versync.yml" do
      with_temp_project do |dir|
        copy_fixture("full_project", dir)
        original = File.read(File.join(dir, ".versync.yml"))
        stderr = StringIO.new

        status = described_class.new(["init"], project_root: dir, stdout: StringIO.new, stderr: stderr).run

        expect(status).to eq(1)
        expect(stderr.string).to include("already exists")
        expect(File.read(File.join(dir, ".versync.yml"))).to eq(original)
      end
    end
  end
```

Add `require "yaml"` near the top of `spec/cli_spec.rb` if not already present (it is, transitively, via `versync`, but add it explicitly for the spec file's own `YAML.safe_load` call).

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/cli_spec.rb -e "init command"`
Expected: FAIL — `status` is `1` for the first example too (stub always returns `1`, no file written), so `.versync.yml` doesn't exist and the read raises.

- [ ] **Step 3: Implement**

In `lib/versync/cli.rb`, add the `PROBES` constant next to `COMMANDS`:
```ruby
    PROBES = {
      "ruby" => { "file" => ".ruby-version", "config" => { "adapter" => "ruby_version" } },
      "rails" => { "file" => "Gemfile.lock", "config" => { "adapter" => "bundler", "gem" => "rails" } },
      "postgres" => { "file" => "docker-compose.yml", "config" => { "adapter" => "docker_compose", "service" => "db" } },
      "redis" => { "file" => "docker-compose.yml", "config" => { "adapter" => "docker_compose", "service" => "redis" } }
    }.freeze
```

Replace:
```ruby
    def run_init
      1
    end
```
with:
```ruby
    def run_init
      if File.exist?(config_path)
        @stderr.puts ".versync.yml already exists"
        return 1
      end

      facts = PROBES.each_with_object({}) do |(fact_name, probe), acc|
        next unless File.exist?(File.join(project_root, probe["file"]))

        acc[fact_name] = probe["config"]
      end

      File.write(config_path, YAML.dump("facts" => facts))
      @stdout.puts "Wrote #{config_path} with #{facts.size} detected fact(s)"
      0
    end
```

Add `require "yaml"` at the top of `lib/versync/cli.rb`.

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/versync/cli.rb spec/cli_spec.rb spec/fixtures/full_project_without_config
git commit -m "Implement versync init command"
```

---

### Task 16: README, packaging check, and end-to-end smoke test

**Files:**
- Create: `README.md`
- Modify: `spec/cli_spec.rb` (add an end-to-end describe block)

**Interfaces:**
- Consumes: the complete `Versync::CLI` public interface from Tasks 12–15.
- Produces: no new library code — this task verifies the whole pipeline works end-to-end through only the public `CLI#run` interface, and that the gem packages correctly.

- [ ] **Step 1: Write the failing end-to-end test**

Add to `spec/cli_spec.rb`:
```ruby
  describe "end-to-end" do
    it "goes from a bare project to a passing check via init, sync, check" do
      with_temp_project do |dir|
        copy_fixture("full_project_without_config", dir)

        init_status = described_class.new(["init"], project_root: dir, stdout: StringIO.new, stderr: StringIO.new).run
        expect(init_status).to eq(0)

        sync_status = described_class.new(["sync"], project_root: dir, stdout: StringIO.new, stderr: StringIO.new).run
        expect(sync_status).to eq(0)

        check_status = described_class.new(["check"], project_root: dir, stdout: StringIO.new, stderr: StringIO.new).run
        expect(check_status).to eq(0)

        markdown = File.read(File.join(dir, "VERSIONS.md"))
        expect(markdown).to include("| rails | 8.1.3 | Gemfile.lock |")
      end
    end

    it "reports check as stale after Gemfile.lock changes post-sync" do
      with_temp_project do |dir|
        copy_fixture("full_project", dir)
        described_class.new(["sync"], project_root: dir, stdout: StringIO.new, stderr: StringIO.new).run

        gemfile_lock = File.join(dir, "Gemfile.lock")
        File.write(gemfile_lock, File.read(gemfile_lock).sub("rails (8.1.3)", "rails (8.2.0)"))

        stderr = StringIO.new
        status = described_class.new(["check"], project_root: dir, stdout: StringIO.new, stderr: stderr).run

        expect(status).to eq(1)
        expect(stderr.string).to include("rails: documented=\"8.1.3\" actual=\"8.2.0\"")
      end
    end
  end
```

- [ ] **Step 2: Run to verify failure or pass**

Run: `bundle exec rspec spec/cli_spec.rb -e "end-to-end"`
Expected: Both examples should already PASS at this point, since every command they exercise was implemented in Tasks 12–15. This step is a regression check, not a new-feature TDD cycle — if either example fails, it indicates a bug in an earlier task's implementation that must be fixed before continuing.

- [ ] **Step 3: Write the README and verify packaging**

`README.md`:
````markdown
# versync

A lockfile tells you which *libraries* a project depends on. It says nothing
about the surrounding *services* — which PostgreSQL, Redis, or RabbitMQ
version the project actually runs against. That information tends to live
scattered across README files, AI-agent context docs, and Docker Compose
files, copied by hand, drifting out of sync as the project evolves.

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
(reads a named service's image tag from `docker-compose.yml`).

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

Run: `gem build versync.gemspec`
Expected: succeeds, producing `versync-0.1.0.gem` (already covered by `.gitignore`'s `*.gem` rule — delete the built file after confirming success, it's not committed).

- [ ] **Step 4: Run the full test suite one final time**

Run: `bundle exec rspec`
Expected: PASS (every example across all 16 tasks).

- [ ] **Step 5: Commit**

```bash
git add README.md spec/cli_spec.rb
git commit -m "Add README and end-to-end smoke tests"
```

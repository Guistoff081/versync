# versync — Design v0.1

Status: approved for implementation
Date: 2026-08-25

## Problem

A lockfile (`Gemfile.lock`, `package.json`) tells you which *libraries* a
project depends on, but says nothing about the surrounding *services* —
which PostgreSQL, Redis, or RabbitMQ version the project actually runs
against. That information tends to live scattered across `README.md`,
`CLAUDE.md`, `AGENTS.md`, `Dockerfile`, `docker-compose.yml` — copied by
hand, and drifting out of sync as the project evolves.

This is a growing problem for AI coding agents specifically: an agent
reading a stale `CLAUDE.md` that says "Rails 8.0" while the app actually
runs Rails 8.1.3 gets a subtly wrong picture of the codebase it's
working in, in a way a lockfile diff or `git log` won't surface.

Renovate/Dependabot already solve "is there a newer version available
upstream?" — that is explicitly **not** this project's job, to avoid
producing a second, redundant signal on top of tools that already do
this well. versync's job is narrower and different: **is the truth we
have written down actually true right now?**

## Origin

This pain shows up repeatedly in real-world Rails codebases — especially
larger, longer-lived ones — where documentation of the runtime
environment (Ruby, Rails, service versions) quietly drifts from reality
over time, and both human contributors and AI coding agents end up
working from an inaccurate mental model as a result. A small internal
script following this same pattern (extract facts from `.ruby-version`,
`Gemfile`/`Gemfile.lock`, and similar sources; produce a human-readable
and JSON representation) validated the approach before this project
generalized it into a standalone, framework-agnostic Ruby gem.

## Goals (v0.1 / MVP)

- Extract version facts from a Ruby/Rails project's own repository
  state (not upstream registries).
- Generate one canonical, always-regenerated file (`VERSIONS.md` +
  `versync.json`) that both humans and AI agents can treat as ground
  truth.
- Provide a CI-friendly `check` command that fails when the canonical
  file is stale relative to the repository's actual state.
- Ship as a small, dependency-light Ruby gem usable in any
  Bundler-managed project (Rails or not).

## Non-goals (v0.1)

- Detecting version drift inside arbitrary free-text docs
  (`README.md`, `CLAUDE.md`, etc.) via inline markers — designed
  conceptually (see Roadmap) but **not implemented** in v0.1.
- Comparing installed versions against the latest upstream release
  (Renovate/Dependabot's job) — explicitly out of scope, see Problem
  section.
- Node/JS fact sources (`package.json` engines/deps) — Ruby/Rails only
  for v0.1.
- Editing/patching arbitrary existing documentation files in place.

## Architecture

### Adapters

Each fact source is a small, isolated adapter implementing a common
interface:

```ruby
class Versync::Adapters::Base
  def name; end
  def available?(project_root); end
  def extract(project_root, config); end # => Versync::Fact
end
```

v0.1 ships three adapters:

| Adapter | Extracts | Reads |
|---|---|---|
| `ruby_version` | Ruby version | `.ruby-version` |
| `bundler` | version of a named gem (e.g. `rails`) | `Gemfile.lock` |
| `docker_compose` | image tag of a named service (e.g. `db`, `redis`) | `docker-compose.yml` |

`docker_compose` extracts the tag portion of the service's `image:`
field (e.g. `image: postgres:18.1-alpine` → value `18.1-alpine`). A
service with no tag (`image: postgres`, implying `latest`) or no
`image:` key (`build:`-only service) is reported as unavailable for
that fact rather than guessed.

The adapter looks for a compose file under the project root, trying
these names in order and using the first one found: `compose.yaml`,
`compose.yml`, `docker-compose.yaml`, `docker-compose.yml` (matching
the Compose Spec's own precedence, since newer tooling favors
`compose.yaml`). The fact's reported `source` names whichever file was
actually found, e.g. `compose.yaml (db)`.

### Unavailable facts

A fact whose adapter cannot extract a value (file missing, service
absent, no tag, unknown gem) is **not** guessed and is **not** silently
dropped: it is omitted from `VERSIONS.md`/`versync.json` for that run,
and `versync facts`/`versync sync` print a one-line warning per skipped
fact to stderr (e.g. `warning: fact 'redis' unavailable — service
'redis' not found in compose.yaml`). This does not change the command's
exit code — an unavailable fact is a normal, expected outcome (e.g. a
project without Redis configured), not a failure.

### Configuration

A project opts in to which facts it wants tracked via `.versync.yml`:

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
  redis:
    adapter: docker_compose
    service: redis
```

`versync init` generates a starting `.versync.yml` by probing which
adapters are applicable to the current repo (presence of
`.ruby-version`, `Gemfile.lock`, `docker-compose.yml`).

### Pipeline

```
.versync.yml
     │
     ▼
Configuration ── declares which facts, which adapters
     │
     ▼
FactsCollector ── runs each configured adapter against project_root
     │
     ▼
  [Fact, Fact, ...]   (name, value, source description)
     │
     ├──▶ Renderers::Markdown  ──▶ VERSIONS.md
     ├──▶ Renderers::Json      ──▶ versync.json
     └──▶ DiffChecker          ──▶ would sync change anything? (for `check`)
```

### Fact

```ruby
Versync::Fact = Struct.new(:name, :value, :source, keyword_init: true)
# Fact.new(name: "rails", value: "8.1.3", source: "Gemfile.lock")
```

### Canonical output

`versync sync` regenerates both files completely from current facts —
never partial edits, always a full deterministic rewrite:

`VERSIONS.md`:
```markdown
<!-- Generated by versync. Do not edit by hand — run `versync sync`. -->

# Repository Facts

| Fact | Version | Source |
|---|---|---|
| Ruby | 4.0.6 | .ruby-version |
| Rails | 8.1.3 | Gemfile.lock |
| PostgreSQL | 18.1 | docker-compose.yml (db) |
| Redis | 8.2 | docker-compose.yml (redis) |

_Last synced: <timestamp> · commit <sha>_
```

`versync.json` carries the same facts as machine-readable data (name,
value, source, generated_at, commit) — this is what AI agents should
read for precise context instead of parsing Markdown.

### CLI

```
versync init     # generate a starting .versync.yml
versync facts    # print current facts to terminal (reads only, writes nothing)
versync sync     # regenerate VERSIONS.md + versync.json
versync check    # exit non-zero if `sync` would change anything — for CI
```

`check` implementation: run the same pipeline as `sync` in memory,
compare the freshly collected facts and the freshly rendered
`VERSIONS.md` body against what's currently on disk, report a diff,
exit non-zero on mismatch. No parsing of unrelated documentation
files.

`check` reports stale (exit 1) when any of the following is true:
- `versync.json` does not exist yet.
- A fact's value or source in `versync.json` differs from what a fresh
  collection produces.
- `VERSIONS.md` does not exist, or its table differs from a fresh
  render (the `_Last synced: ..._` footer line is excluded from this
  comparison — see "Design Decisions Not Explicit In The Spec" in the
  implementation plan for why).

| Command | Exit 0 | Exit 1 |
|---|---|---|
| `init` | `.versync.yml` written | `.versync.yml` already exists |
| `facts` | facts printed (0 or more; unavailable facts warn but don't fail) | `.versync.yml` missing or invalid |
| `sync` | files written | `.versync.yml` missing or invalid |
| `check` | nothing stale | `.versync.yml` missing/invalid, or output stale per the rules above |

Facts are always collected, rendered, and compared in the order
they're declared under `facts:` in `.versync.yml` — output order is
deterministic and config-driven, never alphabetical or adapter-registry
order.

## Repository structure

```
versync/
├── exe/
│   └── versync
├── lib/
│   ├── versync.rb
│   └── versync/
│       ├── version.rb
│       ├── configuration.rb          # reads .versync.yml
│       ├── adapters/
│       │   ├── base.rb
│       │   ├── ruby_version.rb
│       │   ├── bundler.rb
│       │   └── docker_compose.rb
│       ├── fact.rb
│       ├── facts_collector.rb
│       ├── renderers/
│       │   ├── markdown.rb
│       │   └── json.rb
│       ├── diff_checker.rb
│       └── cli.rb
├── test/
│   ├── adapters/
│   ├── renderers/
│   ├── fixtures/                     # sample Gemfile.lock, compose.yaml
│   └── test_helper.rb
├── Rakefile
└── versync.gemspec
```

CI runs `bundle exec rake test` on push/PR via
`.github/workflows/ci.yml`.

## Testing approach

- **Minitest**, not RSpec: it ships in Ruby's standard library, so it
  adds zero runtime/dev dependencies beyond what a "small,
  dependency-light" gem (see Goals) should need, and `rake test` is
  the conventional entry point `bundle gem` itself scaffolds.
- Each adapter tested in isolation against real fixture files
  (`Gemfile.lock`, `compose.yaml` samples) — no adapter mocks.
- `FactsCollector` tested against fake/stub adapters to verify
  orchestration logic independent of real parsing.
- Renderers tested via direct string/JSON assertions on generated
  Markdown/JSON.
- `DiffChecker` tested against a stale `VERSIONS.md`/`versync.json`
  fixture vs. an up-to-date one, verifying correct exit-code behavior.
- Filesystem interactions use real temporary directories with
  fixtures copied in — no filesystem mocking, to catch path/encoding
  bugs early.

## Distribution

Standard RubyGems gem, no Rails dependency:

```
bundle add versync --group development
```

Name availability confirmed on RubyGems (`versync` unclaimed as of
2026-08-25). The unrelated `versync` npm package (JS ecosystem) does
not conflict.

## Roadmap (post-v0.1, not part of this spec's implementation scope)

- **v0.2 — Inline markers in free-text docs.** Opt-in markers like
  `<!--versync:rails-->8.0.2<!--/versync-->` inside `README.md`,
  `CLAUDE.md`, `AGENTS.md` (declared via a `watch:` list in
  `.versync.yml`). `check` flags markers whose enclosed value diverges
  from the current fact; `sync` can surgically replace only the text
  between the marker tags, leaving the rest of the file untouched.
  Deferred because it requires a marker-parsing/rewriting component
  the MVP doesn't need, and the team preferred to prove the core facts
  pipeline first.
- **v0.2/v0.3 — Environment two-way check.** Compare documented facts
  not just against repository files but against the *live*
  environment actually running (e.g. `ruby -v`, `psql --version`,
  `docker --version` output from the local machine or CI runner).
  Extends the same "is the documented truth actually true?" thesis
  from files to a running environment. Explicitly does **not** mean
  checking for newer upstream releases (Renovate/Dependabot's job,
  intentionally out of scope to avoid a redundant/competing signal).
- **v0.3 — Multi-source facts + `propagate`/`bump` (complement to
  Renovate/Dependabot, not a competitor).** Not designed yet — captured
  from a real Ruby upgrade where one version was pinned in 9 places
  (`.ruby-version`, `.mise.toml`, `Gemfile`, `Gemfile.lock`
  `RUBY VERSION`, four Dockerfile `ARG RUBY_VERSION=` lines, a versions
  doc), plus `BUNDLED WITH`, and one agent-context doc still said an
  older patch. Ideas to brainstorm, in order:
  1. *Multi-source facts* — a fact declares every location that pins it
     (`sources:` list); `check` also fails when the sources disagree
     with each other, not only when the output is stale. This is the
     cheapest step and replaces hand-rolled `bin/doc-versions --check`
     scripts.
  2. *`propagate`* — when an external updater (Renovate, Dependabot, a
     human) changes one source, `versync propagate` (or `sync
     --propagate`) rewrites the remaining sources to match and
     regenerates the outputs, so the update PR arrives fully
     consistent. Needs a write side on adapters (surgical replace of
     the matched value, same safety rules as `sync`'s output guard).
  3. *`bump <fact> <version>`* — explicit target version only. versync
     still never queries upstream for the "latest" version; discovery
     stays with Renovate/Dependabot (keeps the Problem-section thesis).
  Open questions: whether lockfile sections (`RUBY VERSION`,
  `BUNDLED WITH`) are rewritten textually or by shelling out to
  `bundle lock`; how a per-repo Renovate config and versync's
  `sources:` avoid listing the same files twice. Constraint from the
  requester: no extra noise or friction in adopting it or running
  upgrades — near-zero new config, one command, no per-project script.
- **Later — Node/JS adapter** (`package.json` engines/deps) if there's
  demand to cover Rails+Hotwire+JS stacks with full fidelity.
- **Later — possible `rails_quality-context` adapter.** If the Rails
  Quality Engine project (see broader portfolio evaluation) proceeds,
  versync's facts pipeline could be reused as one of its adapters
  without versync needing to be redesigned as a plugin from day one.

## Related context

This spec is part of a broader portfolio evaluation of four project
ideas (versync, Rails Quality Engine, Kamal Serverless, SpecEditUI).
versync was chosen to ship first: smallest scope, fastest to a real
release, and immediately useful in the author's own AI-agent-assisted
workflow.

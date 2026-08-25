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

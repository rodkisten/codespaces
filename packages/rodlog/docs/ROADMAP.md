# 🗺️ rodlog roadmap

Features are checked only after implementation and CI validation. Each feature block updates code comments, fixtures, README and architecture docs as appropriate.

## Semantic diagnostics and presentation

- [ ] TypeScript: VS Code / pretty-ts-errors-inspired cards with source lines, caret, expected versus actual types, and human-readable explanations of TS2322, TS2345, TS2307 and other common codes.
- [ ] Group diagnostics by source file and root cause; collapse repeated messages while preserving full raw output.
- [ ] Improve Unicode grapheme and tab-aware caret positioning, including mobile-width terminals.
- [ ] Responsive compact and expanded output modes, with accessible semantic color themes.

## Test runners and Node.js

- [ ] Vitest and Jest: suite/test names, pass/fail/skip counts, durations, assertion diffs and focused failure cards.
- [ ] Node.js built-in `node --test`: TAP/subtest status, assertion failures and stack traces.
- [ ] Node runtime errors: structured exception chains, stack frames, module resolution and exit codes.

## Docker

- [ ] Semantic colors for `docker run`, `docker logs`, `docker compose logs`, not only `docker build`.
- [ ] Container labels, timestamps, health transitions, port bindings and shutdown states.
- [ ] Highlight OOM, permissions, connection failures and exit codes without recoloring existing ANSI.

## Python

- [ ] Python tracebacks: exception-first cards, source locations, cause chaining and readable stack frames.
- [ ] pytest/unittest: test progress, assertion diffs, failure summaries and captured output.
- [ ] pip and common Python tooling: install status, warnings and dependency errors.

## Platform and extensibility

- [ ] TOML configuration, themes and per-tool overrides.
- [ ] Pluggable parsers and additional Git, Terraform and kubectl adapters.
- [ ] SARIF export, release provenance and pinned installer instructions.

## Quality gate for every block

1. Implement and comment on the reasoning behind parser/rendering decisions in the Go source.
2. Add sanitized, representative fixtures and regression tests, including no-color/raw preservation.
3. Update the README with executable examples and refresh architecture diagrams if needed.
4. Run `gofmt`, Go tests and CI before checking off the feature.

The current TypeScript screenshot demonstrates highlighted locations but not yet expected/actual type explanations or a source-code frame for each error. Those are planned enhancements, not implemented features.

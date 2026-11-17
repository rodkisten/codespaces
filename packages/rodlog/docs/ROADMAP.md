# 🗺️ rodlog roadmap

Features are checked only after implementation and CI validation. Each feature block updates code comments, fixtures, README and architecture docs as appropriate.

## Revised priorities and reuse-first architecture (November 2026)

1. **TypeScript first:** accurate diagnostics, source frames, expected/actual types, root-cause grouping. Prefer TypeScript compiler output as the source of truth.
2. **Docker and Dockerfile next:** semantic status highlighting for build/run/logs/compose, Dockerfile syntax and contextual container events.
3. **Shared semantic highlighting engine:** reusable token categories, overlapping-span precedence, configurable themes and mobile-friendly rendering.
4. **Python:** tracebacks, pytest/unittest, pip and dependency diagnostics.
5. **Vitest, Jest and Node test runners last:** continue improving assertion diffs only after the above priorities.

### Existing libraries and projects to reuse

- **[zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting):** architectural reference for pluggable highlighters (`main`, `brackets`, `pattern`, `regexp`) and semantic style keys. It is a Zsh/ZLE implementation, **not** a directly importable Go library.
- **[bat](https://github.com/sharkdp/bat):** presentation reference for syntax definitions, themes, line numbers and code frames. bat uses Rust **syntect** and Sublime syntax definitions; avoid embedding a Rust runtime solely for this.
- **Chroma v2 (already a Go dependency):** default syntax lexer/theme engine for Dockerfile, TypeScript, shell and Python; inspect supported lexers before writing regex replacements.
- **Lip Gloss (already a Go dependency):** terminal styling and layout, without reinventing ANSI formatting.
- **mvdan.cc/sh/v3 (already a Go dependency):** shell AST when semantic shell syntax is needed.

Keep semantic parsing distinct from syntax tokenization and rendering. Preserve original ANSI and byte-for-byte raw output, bound per-line work, and use sanitized fixtures and CI for every block.

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

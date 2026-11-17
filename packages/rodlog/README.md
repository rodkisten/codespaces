# 🌈 rodlog

> **One stream. Many tools. Beautiful diagnostics.** ✨

A small Go-powered streaming highlighter for **npm 📦, TypeScript 🟦, gcloud ☁️, Wrangler ⚡ and Docker 🐳**.

## 🚀 Quick start

From the repository root, after building the binary:

```bash
cd packages/rodlog
go test ./...
go build -o rodlog ./cmd/rodlog
npm run build 2>&1 | ./rodlog --color=always
./rodlog exec --color=always -- npm run build
./rodlog exec --tool=typescript -- npx tsc --noEmit
./rodlog exec --tool=gcloud -- gcloud version
./rodlog exec --tool=wrangler -- npx wrangler --version
./rodlog exec --tool=docker -- docker version
```

## 🧠 Modes

| Mode | What it does |
| --- | --- |
| `enhance` | Preserves original text, adds ANSI token and severity colors |
| `transform` | Renders structured diagnostic cards, source excerpts, suggestions, grouped counts and JSON tables when recognized |
| `raw` | Copies input byte-for-byte |

`--tool=auto` detects recognizable signatures. Force a tool when necessary. `--color=auto|always|never` respects `NO_COLOR` in auto mode.

## 🧪 Tests

```bash
cd packages/rodlog && go test -v ./...
```

Tests cover all five detectors, raw byte preservation, colorization, fallback on renderer errors, long lines and child exit codes.

## 🛠️ Shell hook

```bash
eval "$(rodlog-shell-hook bash)" # after installing the helper
```

Use `rodlog-shell-hook zsh` for Zsh. The hook defines `rlog` as a convenient wrapper and does **not** hijack every command or modify shell startup files automatically.

## 📦 Install

See `scripts/install.sh` and `scripts/shell-hook.sh`. Install from a reviewed pinned release when available. The installer checks SHA-256 digests for release binaries. **A release must be published before remote installation works.**

## 🏗️ Architecture

`io.Reader → streaming frames → detector → Event → renderer`. The core preserves text and falls back to original bytes on renderer errors. Detection is conservative and line-oriented. Semantic adapters, Chroma highlighting, JSONL and GitHub Actions annotations are implemented; more complete multiline parsing and configuration remain future work.

## 🗺️ Roadmap

- [x] Go module, CLI, stream processing and test suite
- [x] npm, TypeScript, gcloud, Wrangler and Docker signatures
- [x] raw/enhance/transform switches and renderer fallback
- [x] Release workflow and shell helper
- [x] Chroma highlighting for confidently recognized source snippets
- [x] Semantic adapters, JSONL and GitHub Actions annotations
- [x] Grouped diagnostic summaries and source frames
- [ ] Multiline diagnostic parsing, TOML config and SARIF
- [ ] Reproducible release verification and signed provenance

💜 Built for terminal-first workflows and mobile Codespaces.

## 🪝 Install with curl or wget

After publishing the first GitHub release:

```bash
curl -fsSL https://raw.githubusercontent.com/rodkisten/codespaces/main/packages/rodlog/scripts/install.sh | sh
# Or:
wget -qO- https://raw.githubusercontent.com/rodkisten/codespaces/main/packages/rodlog/scripts/install.sh | sh
```

To install the **Bash and Zsh hook**:

```bash
curl -fsSL https://raw.githubusercontent.com/rodkisten/codespaces/main/packages/rodlog/scripts/install.sh | RODLOG_INSTALL_HOOK=both sh
```

Use `RODLOG_INSTALL_HOOK=bash` or `zsh` for one shell. Hooks add only a guarded source line to your existing rc file, without overwriting its contents. The helper exposes `rlog`, `rlog-raw` and `rlog-color`. Remove that line and `~/.config/rodlog/hook.sh` to uninstall the hook.

**Security:** a release checksum protects against accidental corruption but is not a signature. Inspect remote shell scripts before executing. The hook download defaults to main and should be pinned to a trusted ref in production.

## 🎬 Five quick demos

```bash
rodlog exec -- npm run build
rodlog exec -- npx tsc --noEmit
rodlog exec -- gcloud run services list
rodlog exec -- npx wrangler deploy --dry-run
rodlog exec -- docker build .
```

For safe demonstrations without invoking cloud services, run `go test -v ./...` or pipe the fixture files under `testdata/`.

## 🎨 Token highlighting (block 3)

Known diagnostics now highlight **TS error codes**, **file:line:column references**, **severity words**, and **CLI names** independently. Existing ANSI escapes are preserved without recoloring. Tests assert that removing added ANSI escapes restores the exact input, including CRLF. Chroma is used selectively for recognized source-code and structured-data snippets; ordinary logs use semantic token highlighting to avoid arbitrary colors.

```bash
go test -race -v ./...
go run ./cmd/rodlog --color=always --tool=typescript < testdata/typescript.log
go run ./cmd/rodlog --color=always --tool=gcloud < testdata/gcloud.log
```

## 🧪🎬 Tests that demonstrate the output

The tests don't just assert behavior: `TestOutputExamples` **prints before/after examples** for npm, TypeScript, gcloud, Wrangler and Docker. In GitHub Actions, open the **🧪 Go tests** step to see the original fixture, highlighted ANSI output, example command and preservation assertion.

```bash
cd packages/rodlog
go test -v -run '^TestOutputExamples$' ./...
go test -race -v ./...
```

The examples are offline and do not deploy to Google Cloud, Cloudflare or Docker. The visible ANSI escape sequences are intentional, so terminal viewers can show colors when supported.


## 📦 Main-branch build artifacts

The **🌈 rodlog · Test & Release** workflow runs only when `packages/rodlog/**` or its workflow changes. PRs run validation; successful pushes to `main` additionally cross-compile four binaries and upload the `rodlog-main-binaries` GitHub Actions artifact, containing SHA-256 checksums. Artifacts expire after 90 days.

Install the latest successful main build (requires GitHub CLI `gh`, authenticated repository access, and `unzip`):

```bash
curl -fsSL https://raw.githubusercontent.com/rodkisten/codespaces/main/packages/rodlog/scripts/install.sh | sh
```

To enable Bash and Zsh helpers:

```bash
curl -fsSL https://raw.githubusercontent.com/rodkisten/codespaces/main/packages/rodlog/scripts/install.sh | RODLOG_INSTALL_HOOK=both sh
```

The installer retrieves the newest successful push workflow run on `main`, downloads the named Actions artifact, verifies the selected platform binary's checksum, and installs to `~/.local/bin/rodlog`. It never builds locally. Because Actions artifacts are not permanent releases, publish a release for long-term retention when needed.


## 🌐 Public release downloads

The installer now downloads platform binaries directly from [rodlog releases](https://rodkisten.github.io/rodlog/releases/) without GitHub CLI authentication. The publishing workflow must first successfully push the binaries to the site repository. Override the mirror with `RODLOG_RELEASE_BASE` if needed. Checksums are verified before installation.

## 🧠 Semantic diagnostic adapters

The stream now carries an optional `Event.Diagnostic` with tool, severity, code, file, line, column and message, without changing the original `Event.Text`. Initial adapters recognize TypeScript (both common location formats), npm warnings/errors/notices, gcloud errors/warnings and Docker build failures or Dockerfile locations. Unknown lines fall back to the existing renderer. Consumers can implement `Renderer.Render(Event)` to produce structured integrations; no subprocess or shell code is evaluated by these parsers.

**Next:** multiline diagnostics, richer Wrangler/npm adapters, JSONL output, GitHub annotations, and AST-backed source analysis with a version-pinned shell parser. Syntax coloring via Chroma is separate from semantic extraction.

### Machine-readable output and GitHub Actions

Use `--output=jsonl` to emit one JSON event per input line (including the original `Text` and optional `Diagnostic`). Use `--output=github` to emit only recognized error/warning workflow annotations. Both work in stdin and `exec` modes. The default `--output=terminal` preserves terminal rendering. `RODLOG_OUTPUT` sets the default output format.

```sh
npm run typecheck 2>&1 | rodlog --tool=typescript --output=jsonl
rodlog exec --tool=typescript --output=github -- npm run typecheck
```

The GitHub annotation format is designed for GitHub Actions log processing. In local terminals, prefer the default renderer. `--output=github` deliberately omits unrecognized lines.

## Automatic command detection

`rodlog tools` prints the built-in executable inventory. `rodlog exec -- gcloud run services list` selects the gcloud adapter before reading any output; explicit `--tool` overrides detection. Unknown commands fall back to generic output. `--mode=transform --color=always` renders recognized diagnostics with a compact, colored heading.

Optional Bash/Zsh wrapping (external executables only, existing aliases/functions preserved):

```sh
export RODLOG_WRAP_COMMANDS=gcloud,docker,npm
source "$HOME/.config/rodlog/hook.sh"
gcloud run services list
```

Shell functions requiring current-shell state are not safe to execute through subprocess wrappers. Use `rlog` explicitly for external programs. Automatic wrapping is disabled by default.

### Shell hook verification and limitations

Run `bash scripts/test-shell-hook.sh` to validate executable wrapping, argument forwarding, exit codes, opt-in behavior, and preservation of existing aliases/functions. Wrapping resolves the external executable path **before** installing a shell function to avoid accidental recursion. Only the built-in allowlist is accepted.

Aliases and shell functions are intentionally **not** overridden. To run an alias or shell function with shell-local state, invoke it normally; to enhance an external command, use `rlog COMMAND ...`. Automatic alias expansion and arbitrary function interception would require shell-specific evaluation and are not enabled.

## Shell semantic AST

`AnalyzeShell(source, dialect)` uses the maintained Go parser `mvdan.cc/sh/v3/syntax` to build a real Bash/POSIX/mksh AST. It returns literal command invocations with source line/column, arguments and matched tool inventory entries. Shell expansions are not executed or guessed. Zsh is explicitly rejected rather than silently interpreted as Bash because this parser does not implement full Zsh grammar. The next integration step will connect the AST to an interactive shell-aware command hook and diagnostic frames.

## Extended diagnostic fixtures

The five `testdata/*.log` files now contain longer **synthetic, realistic examples** modeled on common CLI output formats. They are not verbatim captured production logs and contain no credentials or personal data. Tests exercise preservation of uncolored output, ANSI transform rendering, and structured diagnostic recognition. In transform mode, diagnostic cards display severity, source location and message; unsupported lines retain the original conservative behavior.

### Code frames and summary

In colored transform mode, local relative source files (up to 1 MiB) can provide a five-line diagnostic frame with a column caret. Duplicate structured diagnostics are suppressed and a final error/warning count is printed. Raw, enhance, JSONL and GitHub annotation modes retain their prior behavior. No source is read for absolute or parent-traversal paths.

In colored transform mode, diagnostics are now separated into file/tool sections as their group changes during streaming. This is contiguous grouping, not reordering: interleaved output remains in its original order. The final sorted group summary is unchanged.

## 🎨 Why the colors work this way

The terminal palette is semantic, not a general-purpose syntax rainbow: **red** signals errors, **yellow** warnings, and **green** success. Paths, error codes and tool names receive subtler token-level treatment. Already-colored ANSI input is passed through unchanged. `raw` always preserves bytes; `enhance` preserves text while adding highlights; `transform` can produce diagnostic cards and a final grouped summary.

## 🔍 Reading the source

Start with [`rodlog.go`](rodlog.go) for the streaming engine and `Render` decision tree. Continue with [`semantic.go`](semantic.go) for tool-specific diagnostic extraction, [`highlight.go`](highlight.go) for prioritized non-overlapping color spans, [`syntax.go`](syntax.go) for conservative Chroma detection, and [`diagnostic_render.go`](diagnostic_render.go) for cards and source excerpts. The original text is retained in `Event.Text` even when a structured `Diagnostic` is recognized.

The fixtures under `testdata/` are **synthetic representative examples**, not captured production logs. Use `go test -race ./...` to validate behavior and `go test -v -run TestOutputExamples ./...` for demonstrations.

📐 **Architecture walkthrough:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

🗺️ **Feature roadmap:** [docs/ROADMAP.md](docs/ROADMAP.md), including TypeScript diagnostic cards, Vitest/Node tests, Docker runtime logs and Python tracebacks.

## 🔎 TypeScript explanations (incremental)

In `--mode=transform`, recognized TypeScript diagnostics now add a short semantic explanation for `TS2322`, `TS2345`, `TS2307`, `TS7006` and `TS18048`. For simple assignability messages, the card identifies the **expected** and **received** types. The original compiler message remains authoritative; complex types and multi-line messages are not yet fully parsed. Existing Chroma/Lip Gloss dependencies continue to handle generic highlighting and terminal styling.

```bash
rodlog exec --mode=transform --color=always -- npx tsc --noEmit
```

## 🧪 Test runner adapters (initial support)

`rodlog exec --mode=transform --color=always -- npx vitest run` and `rodlog exec --mode=transform --color=always -- node --test` recognize common failed-test markers and turn them into diagnostic cards. `node --version` remains generic. This is a first step: assertion diffs, stack traces, summary counters and richer suite grouping are still on the [roadmap](docs/ROADMAP.md). Raw and no-color modes continue to preserve the source output.

### Assertion mismatch cards

In transform mode, single-line Vitest and Node assertions such as `AssertionError: expected 3 to be 4` show explicit **Expected: 4** and **Received: 3** labels, while retaining the original error text. This deliberately handles only a narrow, recognizable form; multi-line object diffs and stacks remain a follow-up.

## 🐳 Docker runtime and Dockerfile highlighting

The Docker adapter now colors selected container health/lifecycle/error tokens in `docker run`, `docker logs` and `docker compose logs`, while preserving timestamps, service prefixes and existing ANSI. Recognized Dockerfile instruction lines use the **existing Chroma Dockerfile lexer**, not a custom lexer. Example: `rodlog exec --tool=docker --color=always -- docker compose logs --follow`. This is an incremental semantic layer; multi-container grouping and complete event coverage remain on the roadmap.

### BuildKit steps

BuildKit output from `docker build --progress=plain` and `docker compose build --progress=plain` gets contextual highlighting: **CACHED** is dim, **DONE/FINISHED** green, **ERROR** red, and active export/transfer steps cyan. Step IDs, commands and timings remain intact. Existing ANSI remains untouched.

```bash
rodlog exec --tool=docker --color=always -- docker build --progress=plain .
rodlog exec --tool=docker --color=always -- docker compose build --progress=plain
```

## 🪝 Codespaces automatic installation and shell wrappers

The repository's `scripts/bootstrap.sh create|start` builds `rodlog` into `~/.local/bin` from the checked-out Go source (when Go is installed). The interactive `zsh/zshrc` loads the existing shell hook and enables conservative wrappers for `gcloud,docker,npm,tsc,wrangler`. Existing aliases/functions are respected. Use `RODLOG_BOOT_INSTALL=0` to skip building or `RODLOG_WRAP_COMMANDS=''` to disable wrappers. For any other command use `rlog <command> ...` explicitly. This is **not** a universal transparent interceptor: arbitrary pipelines, shell builtins and redirected commands cannot be safely intercepted without altering shell semantics.

### BuildKit highlighting correction

BuildKit status recognition now uses correct Go regexp escapes. Active operations such as `exporting` highlight only the operation token, preserving step IDs, stage labels, commands and timings. Existing raw and no-color behavior is unchanged.

### Vite-style BuildKit step headers

When color is enabled, Dockerfile instruction headers become muted-background `STEP N` badges with Chroma syntax highlighting (original text fallback), followed by a subtle separator. Repeated headers are suppressed; BuildKit status and timing lines remain visible. Raw and no-color modes preserve original bytes. Separator customization via TOML is planned.

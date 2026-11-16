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
| `transform` | Adds tool-aware informational coloring; richer layouts planned |
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

`io.Reader → streaming frames → detector → Event → renderer`. The core preserves text and falls back to original bytes on renderer errors. Current detection is conservative and line-oriented; multiline semantic diagnostics, TOML configuration, JSONL, GitHub annotations and Chroma highlighting and semantic adapters remain on the roadmap.

## 🗺️ Roadmap

- [x] Go module, CLI, stream processing and test suite
- [x] npm, TypeScript, gcloud, Wrangler and Docker signatures
- [x] raw/enhance/transform switches and renderer fallback
- [x] Release workflow and shell helper
- [ ] Rich Chroma syntax spans and multiline diagnostics
- [ ] TOML config, semantic adapters and JSONL
- [ ] GitHub annotations, summary and SARIF
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

Known diagnostics now highlight **TS error codes**, **file:line:column references**, **severity words**, and **CLI names** independently. Existing ANSI escapes are preserved without recoloring. Tests assert that removing added ANSI escapes restores the exact input, including CRLF. No Chroma dependency yet: this is a lightweight token highlighter, with language lexing planned next.

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

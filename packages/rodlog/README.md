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

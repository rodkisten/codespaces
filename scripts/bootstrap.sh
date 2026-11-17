#!/usr/bin/env bash
set -Eeuo pipefail
phase="${1:-start}"
case "$phase" in create|start|attach) ;; *) echo "Usage: bootstrap.sh {create|start|attach}" >&2; exit 2;; esac
logdir="$HOME/.local/state/rod-codespaces/logs"
mkdir -p "$logdir"
log="$logdir/${phase}.log"
exec > >(tee -a "$log") 2>&1
echo
echo "=== Rod Codespaces / $phase ==="
date -u '+UTC %Y-%m-%dT%H:%M:%SZ'
echo "User: $(id -un) | Home: $HOME | Workspace: $PWD"
trap 'status=$?; echo "=== phase '"$phase"' finished (exit $status) ==="; exit "$status"' EXIT
if [[ "$phase" == start || "$phase" == create ]]; then
  repo="${CODESPACE_VSCODE_FOLDER:-$PWD}"
  source_file="$repo/zsh/zshrc"
  if [[ -f "$source_file" ]]; then
    if [[ -e "$HOME/.zshrc" && ! -L "$HOME/.zshrc" ]]; then
      cp -n "$HOME/.zshrc" "$HOME/.zshrc.pre-rod-backup"
    fi
    ln -sfn "$source_file" "$HOME/.zshrc"
    echo "Linked ~/.zshrc -> $source_file"
  else
    echo "WARN: $source_file not found; preserving current ~/.zshrc"
  fi
fi
if [[ "$phase" == create || "$phase" == start ]]; then
  repo="${CODESPACE_VSCODE_FOLDER:-$PWD}"
  if [[ -f "$repo/scripts/tailscale.sh" ]]; then
    bash "$repo/scripts/tailscale.sh" auto || echo "WARN: Tailscale daemon or authentication unavailable"
  fi
fi
if [[ "$phase" == create || "$phase" == start ]]; then
  repo="${CODESPACE_VSCODE_FOLDER:-$PWD}"
  if [[ -f "$repo/scripts/rod-check" ]]; then
    mkdir -p "$HOME/.local/bin"
    install -m 0755 "$repo/scripts/rod-check" "$HOME/.local/bin/rod-check"
    echo "Installed global rod-check -> $HOME/.local/bin/rod-check"
  else
    echo "WARN: rod-check script missing; skipping"
  fi
fi
# Install rodlog from this checkout when Go is available. Avoid a remote
# release dependency at boot: the shell always matches the checked-out source.
# A failed optional build must never make the Codespace unusable.
if [[ "$phase" == create || "$phase" == start ]]; then
  repo="${CODESPACE_VSCODE_FOLDER:-$PWD}"
  if [[ "${RODLOG_BOOT_INSTALL:-1}" != 0 && -f "$repo/packages/rodlog/go.mod" ]]; then
    if command -v go >/dev/null 2>&1; then
      mkdir -p "$HOME/.local/bin"
      echo "[RUN] rodlog: building from $repo/packages/rodlog"
      if (cd "$repo/packages/rodlog" && go build -o "$HOME/.local/bin/rodlog" ./cmd/rodlog); then
        echo "[OK] rodlog installed: $HOME/.local/bin/rodlog"
      else
        echo "[WARN] rodlog build failed; existing binary, if any, remains available"
      fi
    else
      echo "[SKIP] rodlog: Go toolchain not available"
    fi
  else
    echo "[SKIP] rodlog: disabled or source unavailable"
  fi
fi
if [[ "$phase" == create || "$phase" == start ]]; then
  if command -v mobile-doctor >/dev/null 2>&1; then
    mobile-doctor || echo "WARN: doctor reported missing tools"
  else
    echo "WARN: mobile-doctor not available"
  fi
fi
echo "Log: $log"

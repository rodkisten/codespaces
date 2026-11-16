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
  if command -v mobile-doctor >/dev/null 2>&1; then
    mobile-doctor || echo "WARN: doctor reported missing tools"
  else
    echo "WARN: mobile-doctor not available"
  fi
fi
echo "Log: $log"

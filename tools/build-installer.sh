#!/usr/bin/env bash
# Regenera install.sh com um .devcontainer compactado e embutido.
# Execute toda vez que alterar o Dockerfile, zshrc, nanorc ou doctor.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
for tool in tar gzip base64; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Falta: $tool" >&2; exit 1; }
done
(
  cat "$ROOT/tools/installer.header.sh"
  # gzip -n não grava timestamp/nome, permitindo builds reproduzíveis.
  tar -C "$ROOT" -cf - .devcontainer | gzip -n -9 | base64 -w 76
  cat "$ROOT/tools/installer.footer.sh"
) > "$ROOT/install.sh"
chmod 0755 "$ROOT/install.sh"
bash -n "$ROOT/install.sh"
echo "Criado: $ROOT/install.sh ($(wc -c < "$ROOT/install.sh") bytes)"

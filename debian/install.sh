#!/usr/bin/env bash
# Rod Debian Bootstrap: idempotent Debian developer workstation / VM.
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
TARGET_USER="${SUDO_USER:-${USER:-root}}"
[[ "$TARGET_USER" == root ]] && TARGET_USER=rod
INSTALL_PACKAGES=1
INSTALL_LANGUAGES=1
INSTALL_TAILSCALE=0
CLONE_REPOS=0
DRY_RUN=0
EXTRA=()
usage() {
cat <<'EOF'
Rod Debian Bootstrap 🐧
Usage: bash install.sh [--user NAME] [--packages-only] [--no-languages]
  [--tailscale] [--clone] [--extra "package1 package2"] [--dry-run]
Run as root (or sudo). Re-running skips installed packages and existing repos.
EOF
}
while (($#)); do
 case "$1" in
 --user) TARGET_USER="${2:?Missing user}"; shift;;
 --packages-only) INSTALL_LANGUAGES=0;;
 --no-languages) INSTALL_LANGUAGES=0;;
 --tailscale) INSTALL_TAILSCALE=1;;
 --clone) CLONE_REPOS=1;;
 --extra) read -r -a new <<< "${2:?Missing packages}"; EXTRA+=("${new[@]}"); shift;;
 --dry-run) DRY_RUN=1;;
 --help|-h) usage; exit 0;;
 *) printf 'Unknown option: %s\n' "$1" >&2; exit 2;;
 esac
 shift
done
[[ "$EUID" == 0 ]] || { echo 'Run with sudo or as root.' >&2; exit 1; }
[[ "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo 'Invalid username.' >&2; exit 2; }
log() { printf '\033[36m●\033[0m %s\n' "$*"; }
run() { if (( DRY_RUN )); then printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }
if ! id "$TARGET_USER" >/dev/null 2>&1; then
 log "Creating user $TARGET_USER"
 run useradd -m -s /bin/bash "$TARGET_USER"
 log 'Set a password manually with passwd, or configure SSH keys.'
fi
if (( DRY_RUN == 0 )); then
 HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
else
 HOME_DIR="/home/$TARGET_USER"
fi
packages=(sudo ca-certificates curl wget git gnupg lsb-release unzip zip tar xz-utils
 build-essential pkg-config make cmake ninja-build gcc g++ clang llvm
 openssh-client openssh-server rsync jq yq gh ripgrep fzf fd-find bat
 zsh micro vim nano tmux htop btop tree ncdu less file lsof
 dnsutils iproute2 iputils-ping net-tools tcpdump
 python3 python3-pip python3-venv pipx sqlite3
 golang-go cargo rustc nodejs npm
 git-lfs shellcheck direnv zoxide)
packages+=("${EXTRA[@]}")
log 'Updating package metadata'
run apt-get update
for pkg in "${packages[@]}"; do
 if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -qx 'install ok installed'; then
   log "SKIP installed: $pkg"
 else
   log "INSTALL: $pkg"
   if (( DRY_RUN )); then echo "[dry-run] apt-get install -y $pkg"; else
     if ! apt-get install -y "$pkg"; then log "WARN: could not install $pkg (continuing)"; fi
   fi
 fi
done
if getent group sudo >/dev/null; then run usermod -aG sudo "$TARGET_USER"; fi
run mkdir -p "$HOME_DIR/code" "$HOME_DIR/.local/bin" "$HOME_DIR/.config"
run chown -R "$TARGET_USER:$TARGET_USER" "$HOME_DIR/code" "$HOME_DIR/.local" "$HOME_DIR/.config"
if command -v zsh >/dev/null; then run usermod -s "$(command -v zsh)" "$TARGET_USER"; fi
if (( INSTALL_LANGUAGES )); then
 log 'Installing uv, rustup and zplug for non-root user'
 if (( !DRY_RUN )); then
  if [[ ! -x "$HOME_DIR/.local/bin/uv" ]]; then
   su - "$TARGET_USER" -s /bin/bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh' || log 'WARN uv install failed'
  fi
  if [[ ! -x "$HOME_DIR/.cargo/bin/rustup" ]]; then
   su - "$TARGET_USER" -s /bin/bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path' || log 'WARN rustup install failed'
  fi
  if [[ ! -d "$HOME_DIR/.zplug" ]]; then
   su - "$TARGET_USER" -s /bin/bash -c 'git clone --depth 1 https://github.com/zplug/zplug.git ~/.zplug' || log 'WARN zplug clone failed'
  fi
 fi
fi
# Install or update Rod Prompt without overwriting the user's existing Zsh config.
if (( DRY_RUN )); then
 log "Would install Rod Prompt for $TARGET_USER"
else
 theme_dir="$HOME_DIR/.config/zsh"
 run mkdir -p "$theme_dir"
 theme_tmp="$(mktemp)"
 if curl -fsSL --max-time 20 "https://raw.githubusercontent.com/rodkisten/codespaces/main/.devcontainer/zsh/rod-mobile.zsh-theme" -o "$theme_tmp"; then
   install -m 0644 "$theme_tmp" "$theme_dir/rod-prompt.zsh"
   chown "$TARGET_USER:$TARGET_USER" "$theme_dir/rod-prompt.zsh"
   touch "$HOME_DIR/.zshrc"
   if ! grep -Fq 'source "$HOME/.config/zsh/rod-prompt.zsh"' "$HOME_DIR/.zshrc"; then
     printf '\n# Rod Prompt Neon\nsource "$HOME/.config/zsh/rod-prompt.zsh"\n' >> "$HOME_DIR/.zshrc"
   fi
   chown "$TARGET_USER:$TARGET_USER" "$HOME_DIR/.zshrc"
   log 'Rod Prompt Neon configured'
 else
   log 'WARN: Rod Prompt download failed; keeping existing shell config'
 fi
 rm -f "$theme_tmp"
fi
if (( INSTALL_TAILSCALE )); then
 log 'Installing Tailscale (login is manual)'
 if (( DRY_RUN )); then echo '[dry-run] install tailscale'; else
  curl -fsSL https://tailscale.com/install.sh | sh || log 'WARN Tailscale install failed'
 fi
fi
if (( CLONE_REPOS )); then
 log 'Cloning repositories from GitHub (requires gh authentication)'
 if command -v gh >/dev/null && (( !DRY_RUN )); then
  su - "$TARGET_USER" -s /bin/bash -c 'cd ~/code && gh repo list rodkisten --limit 200 --json nameWithOwner --jq ".[].nameWithOwner" | while read -r repo; do name="${repo##*/}"; if [ -d "$name/.git" ]; then echo "SKIP $name"; else gh repo clone "$repo" "$name" || true; fi; done'
 else log 'SKIP clone: install and authenticate gh first (gh auth login)'; fi
fi
log 'Done. Run: su - '"$TARGET_USER"
log 'To enable Notify!: curl -fsSL https://raw.githubusercontent.com/rodkisten/codespaces/main/notify/install.sh | bash'

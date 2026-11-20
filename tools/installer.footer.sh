ROD_MOBILE_EMBEDDED_ARCHIVE

test -f "$STAGING/.devcontainer/Dockerfile" || fail 'Pacote incompleto: Dockerfile ausente.'
test -f "$STAGING/.devcontainer/devcontainer.json" || fail 'Pacote incompleto: devcontainer.json ausente.'

# Backups com nome único, no mesmo diretório do arquivo substituído.
backup_existing() {
  local path="$1" backup stamp
  [[ -e "$path" || -L "$path" ]] || return 0
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  backup="${path}.backup-${stamp}"
  local n=0
  while [[ -e "$backup" || -L "$backup" ]]; do
    n=$((n + 1))
    backup="${path}.backup-${stamp}-${n}"
  done
  mv -- "$path" "$backup"
  log "Backup: $backup"
}

preflight_path() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]] && (( !FORCE )); then
    fail "Já existe: $path. Use --force para fazer backup e substituir."
  fi
}

install_devcontainer() {
  local target_path="$TARGET/.devcontainer"
  preflight_path "$target_path"
  if (( DRY_RUN )); then
    log "Simulação: copiaria .devcontainer/ para $target_path"
    return
  fi
  backup_existing "$target_path"
  cp -a -- "$STAGING/.devcontainer" "$target_path"
  log "Devcontainer instalado em $target_path"
  log 'Próximo passo: reconstruir o Codespace (Codespaces: Rebuild Container).'
}

install_shell() {
  local home="${HOME:?HOME não configurado}"
  local zshrc="$home/.zshrc"
  local config="$home/.config/zsh"
  local zinit_home="${XDG_DATA_HOME:-$home/.local/share}/zinit/zinit.git"
  command -v zsh >/dev/null 2>&1 || fail 'Zsh ausente.'
  command -v git >/dev/null 2>&1 || fail 'Git ausente.'
  for path in "$STAGING/.devcontainer/zsh/rod-prompt-neon.zsh" "$STAGING/.devcontainer/zsh/rod-prompt-neon.config.zsh" "$STAGING/.devcontainer/zsh/rod-zinit.zshrc"; do
    [[ -s "$path" ]] || fail "Arquivo ausente: $path"
    zsh -n "$path" || fail "Sintaxe Zsh inválida: $path"
  done
  if (( DRY_RUN )); then
    log "Simulação: Zinit + Neon em $config; ~/.zshrc preservado"
    return
  fi
  mkdir -p "$config" "$home/.local/bin" "$(dirname "$zinit_home")"
  if [[ ! -f "$zinit_home/zinit.zsh" ]]; then
    git clone --depth 1 https://github.com/zdharma-continuum/zinit.git "$zinit_home" || fail 'Não foi possível instalar Zinit.'
  fi
  backup_existing "$config/rod-prompt.zsh"
  cp "$STAGING/.devcontainer/zsh/rod-prompt-neon.zsh" "$config/rod-prompt.zsh"
  cp "$STAGING/.devcontainer/zsh/rod-zinit.zshrc" "$config/rod-zinit.zshrc"
  if [[ ! -e "$config/rod-prompt-neon.config.zsh" ]]; then
    cp "$STAGING/.devcontainer/zsh/rod-prompt-neon.config.zsh" "$config/rod-prompt-neon.config.zsh"
  fi
  local source_line='[[ -r "$HOME/.config/zsh/rod-zinit.zshrc" ]] && source "$HOME/.config/zsh/rod-zinit.zshrc"'
  if [[ -L "$zshrc" ]]; then
    warn "~/.zshrc é symlink: preservado. Adicione manualmente: $source_line"
  else
    [[ -f "$zshrc" ]] && cp -p "$zshrc" "$zshrc.backup-$(date -u +%Y%m%dT%H%M%SZ)"
    touch "$zshrc"
    grep -Fqx "$source_line" "$zshrc" || printf '\n# Rod Codespaces · Zinit + Neon\n%s\n' "$source_line" >> "$zshrc"
    zsh -n "$zshrc" || fail 'Erro de sintaxe no ~/.zshrc após instalação.'
  fi
  log 'Zinit + Rod Prompt Neon instalados. Execute: exec zsh'
}

case "$MODE" in
  devcontainer) install_devcontainer ;;
  shell) install_shell ;;
  both)
    # Preflight combinado para evitar uma instalação parcial por conflito de dotfiles.
    preflight_path "$TARGET/.devcontainer"
    install_shell
    install_devcontainer
    ;;
esac
log 'Concluído.'
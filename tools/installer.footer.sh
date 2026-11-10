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
  local plugin_root="$home/.oh-my-zsh/custom/plugins"
  local theme_path="$home/.oh-my-zsh/custom/themes/rod-mobile.zsh-theme"
  local zshrc="$home/.zshrc"
  local nanorc="$home/.nanorc"
  local doctor="$home/.local/bin/mobile-doctor"

  command -v git >/dev/null 2>&1 || fail 'Git é necessário para instalar Oh My Zsh e plugins.'
  command -v zsh >/dev/null 2>&1 || fail 'Zsh não encontrado. Use --devcontainer ou instale o pacote zsh primeiro.'
  if [[ -e "$home/.oh-my-zsh" && ! -f "$home/.oh-my-zsh/oh-my-zsh.sh" ]]; then
    fail "Existe ~/.oh-my-zsh, mas parece incompleto. Verifique manualmente antes de continuar."
  fi
  for path in "$theme_path" "$zshrc" "$nanorc" "$doctor"; do
    preflight_path "$path"
  done
  if (( DRY_RUN )); then
    log "Simulação: instalaria Oh My Zsh e plugins se necessários; copiaria arquivos para $home"
    return
  fi
  if [[ ! -f "$home/.oh-my-zsh/oh-my-zsh.sh" ]]; then
    log 'Instalando Oh My Zsh sem executar instaladores remotos...'
    git clone --quiet --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$home/.oh-my-zsh"
  fi
  mkdir -p -- "$plugin_root" "$home/.oh-my-zsh/custom/themes" "$home/.local/bin"
  local entries=(
    'zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions.git'
    'zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting.git'
    'zsh-completions|https://github.com/zsh-users/zsh-completions.git'
  )
  local entry name url
  for entry in "${entries[@]}"; do
    name="${entry%%|*}"
    url="${entry#*|}"
    if [[ ! -e "$plugin_root/$name" ]]; then
      log "Plugin: $name"
      git clone --quiet --depth=1 "$url" "$plugin_root/$name"
    fi
  done
  for path in "$theme_path" "$zshrc" "$nanorc" "$doctor"; do
    backup_existing "$path"
  done
  cp -- "$STAGING/.devcontainer/zsh/zshrc" "$zshrc"
  cp -- "$STAGING/.devcontainer/nano/nanorc" "$nanorc"
  cp -- "$STAGING/.devcontainer/zsh/rod-mobile.zsh-theme" "$theme_path"
  cp -- "$STAGING/.devcontainer/scripts/doctor.sh" "$doctor"
  chmod 0755 "$doctor"
  zsh -n "$zshrc"
  zsh -n "$theme_path"
  log 'Configuração do shell instalada. Execute: exec zsh'
  warn 'O modo --shell não instala as CLIs do Dockerfile. Para todas as ferramentas, use --devcontainer e reconstrua.'
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
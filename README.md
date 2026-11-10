# Rod Mobile Codespaces 📱

Um kit portátil de desenvolvimento para usar no **GitHub Codespaces pelo iPhone**: Dockerfile Debian, Zsh/Oh My Zsh, prompt compacto de duas linhas, Nano com soft wrap, Node, Python + uv, gcloud, Wrangler, kubectl e utilitários.

## Instalação com um único `curl`

Publique este repositório no GitHub (público, caso queira fazer `curl` sem autenticação). Troque `rodkisten/codespaces` pelo caminho real do seu repositório:

```bash
curl -fsSL https://raw.githubusercontent.com/rodkisten/codespaces/main/install.sh | bash
```

Rode o comando **a partir da raiz do repositório do projeto** que receberá a pasta `.devcontainer/`.

A instalação padrão **não executa Docker nem altera o shell atual**. Ela instala a configuração do devcontainer. Para instalar as ferramentas, depois escolha no Codespaces **Command Palette → Codespaces: Rebuild Container**. Essa reconstrução é necessária porque Dockerfile/`devcontainer.json` não modificam um container em execução.

### Se o projeto já tiver `.devcontainer/`

O instalador **não sobrescreve** configurações existentes sem `--force`:

```bash
curl -fsSL https://raw.githubusercontent.com/rodkisten/codespaces/main/install.sh | bash -s -- --force
```

O diretório antigo é movido para `.devcontainer.backup-AAAAmmddTHHMMSSZ` antes da instalação nova. **Atenção:** neste caso é feita a troca do diretório inteiro, não o merge de configurações existentes.

### Instalar só Zsh/tema/Nano no Codespace que já está aberto

```bash
curl -fsSL https://raw.githubusercontent.com/rodkisten/codespaces/main/install.sh | bash -s -- --shell --force
exec zsh
```

Esse modo instala as configurações `~/.zshrc`, `~/.nanorc`, o tema, Oh My Zsh (se necessário), três plugins extras e `~/.local/bin/mobile-doctor`. Exige **Zsh e Git já instalados**. Não instala o stack completo (Node, Python, gcloud, etc.). O `--force` cria backups individuais dos arquivos existentes.

**Importante:** alterações feitas apenas no `$HOME` de um Codespace podem desaparecer quando o container for reconstruído. Se quiser persistência da imagem inteira, use o modo padrão `.devcontainer/`.

### Outros comandos

```bash
# Prévia sem tocar em nada
curl -fsSL https://raw.githubusercontent.com/rodkisten/codespaces/main/install.sh | bash -s -- --dry-run

# Instalar em outra pasta
curl -fsSL https://raw.githubusercontent.com/rodkisten/codespaces/main/install.sh | bash -s -- --target /workspaces/outro-projeto

# Devcontainer + personalização do shell atual
curl -fsSL https://raw.githubusercontent.com/rodkisten/codespaces/main/install.sh | bash -s -- --both --force
```

Para maior controle, baixe, inspecione e execute localmente:

```bash
curl -fsSLo /tmp/rod-mobile-install.sh https://raw.githubusercontent.com/rodkisten/codespaces/main/install.sh
less /tmp/rod-mobile-install.sh
bash /tmp/rod-mobile-install.sh
```

## Como manter este repositório

```text
.
├── install.sh                          # Instalador autocontido: o único arquivo acessado por curl
├── README.md
├── .devcontainer/
│   ├── Dockerfile
│   ├── devcontainer.json
│   ├── nano/nanorc
│   ├── scripts/doctor.sh
│   └── zsh/
│       ├── zshrc
│       └── rod-mobile.zsh-theme
└── tools/
    ├── build-installer.sh              # Regera o install.sh
    ├── installer.header.sh
    └── installer.footer.sh
```

O arquivo `install.sh` **já contém uma cópia compactada e embutida** da pasta `.devcontainer/`. Isso permite que um único `curl` instale tudo sem exigir API do GitHub, branch fixada no script ou ZIP de release.

Sempre que editar arquivos de `.devcontainer/`, **regenere o `install.sh`** e faça commit dos arquivos juntos:

```bash
bash tools/build-installer.sh
git add .devcontainer install.sh tools README.md
git commit -m 'Update mobile devcontainer'
git push
```

O script não cria tokens nem executa login em serviços, não toca em permissões, projetos ou billing da Cloudflare/GCP, e não modifica os arquivos de código do seu projeto.
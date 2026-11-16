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

## Tailscale no Codespace (sem Sync)

O cliente Tailscale é instalado na imagem e o daemon é iniciado automaticamente
pelos hooks `postCreate` e `postStart` em modo userspace, sem `/dev/net/tun`.
O estado fica em `~/.local/state/rod-codespaces/tailscale/`, com permissões
restritas. Não há importação de credenciais, login automático nem exposição
pública de portas. A autenticação inicial exige confirmação:

```bash
bash scripts/tailscale.sh up       # abre o fluxo de login
bash scripts/tailscale.sh status   # verifica conexão
bash scripts/tailscale.sh ip       # IP privado
bash scripts/tailscale.sh logs     # diagnóstico do daemon
```

**Atenção:** userspace não cria uma interface de rede do sistema. Para conexões
SSH/SFTP a outros dispositivos da tailnet, use um proxy compatível com
Tailscale (por exemplo `tailscale nc`) ou configure um SOCKS5 explícito.
`ssh usuario@100.x.y.z` direto pode não funcionar nesse modo.
O daemon reconecta automaticamente após o reinício quando o estado autenticado
persistir; se o estado não persistir após um rebuild, será necessário autenticar novamente.

### Login automático com secret do Codespaces

Cadastre `TAILSCALE_AUTHKEY` em [GitHub Codespaces secrets](https://github.com/settings/codespaces)
e conceda acesso ao repositório `rodkisten/codespaces`. O bootstrap inicia o
daemon e usa essa chave **apenas quando ainda não está conectado**.
O segredo não é escrito nos logs nem passado diretamente como argumento de processo;
é armazenado temporariamente em arquivo privado, removido após a tentativa.
O estado autenticado é mantido no diretório local do Codespace.

```bash
bash scripts/tailscale.sh auto
bash scripts/tailscale.sh status
bash scripts/tailscale.sh ip
```

Se a chave expirar, substitua o secret e execute `bash scripts/tailscale.sh auto`.
Uma auth key de registro não é a mesma coisa que uma API key.


## Rod Check: diagnósticos compartilháveis 🔎

O bootstrap instala `scripts/rod-check` como `~/.local/bin/rod-check` nos eventos `create` e `start`. O comando fica disponível em **qualquer repositório** aberto no mesmo Codespace, sem copiar o script para cada projeto. A configuração Zsh já inclui `~/.local/bin` no PATH.

Para instalar imediatamente no Codespace atual, sem rebuild:

```bash
bash scripts/bootstrap.sh start
command -v rod-check
cd /workspaces/SEU_REPOSITORIO
rod-check --full
```

Os resultados ficam em `RodCheck/AAAAmmddTHHMMSSZ/`, uma pasta **visível no Termius SFTP**. Envie o arquivo `rod-check-share.tar.gz` dessa pasta. O relatório e JSON estruturado estão no subdiretório `share/`. Logs originais ficam em `logs/` e não entram no pacote compartilhável.

`rod-check` executa os scripts existentes `typecheck`, `lint`, `build`; `--full` acrescenta `test`, `check`, `validate`, `build/validate-changed.sh run` e `fallow audit`, quando disponíveis. Comandos ausentes são ignorados. Por padrão não instala dependências; `--install` permite `npm ci --ignore-scripts` quando existe lockfile. Verifique o pacote antes de compartilhá-lo: o mascaramento automático é limitado.

Adicione `RodCheck/` ao `.gitignore` dos projetos onde executar o diagnóstico para evitar commits acidentais dos logs.

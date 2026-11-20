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

O fluxo atualizado nos fontes instala Zinit + Neon e preserva `~/.zshrc`; o `install.sh` gerado precisa ser atualizado antes de utilizar este modo. Exige **Zsh e Git já instalados**. Não instala o stack completo (Node, Python, gcloud, etc.). O `--force` cria backups individuais dos arquivos existentes.

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

## 🔔 Rod Notify: comandos demorados no Zsh

Instalação independente, sem substituir seu tema, plugins ou configurações existentes:

```bash
curl -fsSL https://raw.githubusercontent.com/rodkisten/codespaces/main/notify/install.sh | bash
exec zsh
```

Configure o Relay no arquivo privado `~/.config/rod-notify/config`:

```bash
ROD_NOTIFY_URL="https://SEU-RELAY/notifications/send"
ROD_NOTIFY_TOKEN="SEU_BEARER_TOKEN"
```

O endereço acima é um **exemplo**, não um endpoint confirmado. Use a URL HTTPS real do Relay e o token correspondente. O script envia JSON com `title` e `message`; adapte `notify/send.sh` caso a API exija outro formato.

Opções para colocar no `~/.zshrc`, **antes** da linha que carrega `rod-notify.zsh`:

| Variável | Padrão | Função |
|---|---|---|
| `ROD_NOTIFY_THRESHOLD` | `10` | Duração mínima em segundos |
| `ROD_NOTIFY_SUCCESS` | `1` | Notificar sucesso |
| `ROD_NOTIFY_FAILURE` | `1` | Notificar erro |
| `ROD_NOTIFY_IGNORE_INTERACTIVE` | `1` | Ignorar SSH, editores, paginadores e monitores |
| `ROD_NOTIFY_HOSTNAME` | `1` | Reservado para identificação da máquina |

Teste: `sleep 11` e depois `false` (este último só notifica se exceder o limite). Para testar uma falha demorada: `sleep 11; false` executado como um único comando de linha.

**Segurança:** o comando completo não é enviado, apenas o primeiro token, nome do diretório, duração e código de saída. Não versionar o arquivo de configuração. O envio é assíncrono, com timeout de 8 segundos; o terminal não aguarda a rede. A integração exige Zsh, curl e Python 3.


## 🐧 Debian VM: instalação completa

Este instalador é **diferente** do `install.sh` da raiz: ele prepara uma VM Debian real. Execute como root ou com `sudo`. Ele não configura firewall, SSH público nem altera regras de acesso à VM.

```bash
curl -fsSL https://raw.githubusercontent.com/rodkisten/codespaces/main/debian/install.sh -o /tmp/rod-debian.sh
sudo bash /tmp/rod-debian.sh --user rod
```

> Segurança: revise o script antes de executá-lo com privilégios de root. Para instalação não interativa, o usuário criado não recebe senha automaticamente; configure SSH autorizado e/ou senha manualmente.

### 🧰 Comandos e opções

| Opção | Ação |
|---|---|
| `--user rod` | Cria usuário `rod` se ausente, adiciona ao grupo sudo e configura Zsh |
| `--extra "httpie ncdu"` | Adiciona pacotes APT sem reinstalar os existentes |
| `--no-languages` | Ignora instalação de uv, rustup e Zplug |
| `--packages-only` | Instala pacotes APT e prepara o usuário, sem linguagens extras |
| `--tailscale` | Instala cliente Tailscale; autenticação separada |
| `--clone` | Clona repos públicos/privados acessíveis via `gh`, quando instalado e autenticado |
| `--dry-run` | Simula as ações principais |

```bash
# Atualizar pacotes ausentes e instalar extras
sudo bash /tmp/rod-debian.sh --user rod --extra "httpie neovim"

# Instalar Tailscale, sem autenticar automaticamente
sudo bash /tmp/rod-debian.sh --user rod --tailscale

# Prévia
sudo bash /tmp/rod-debian.sh --user rod --dry-run

# Clonar repositórios em ~/code (após instalar e autenticar gh)
sudo bash /tmp/rod-debian.sh --user rod --clone
```

Inclui ferramentas de build, Git, SSH, Zsh, fzf, ripgrep, fd, bat, micro, zoxide, Go, Rust, Node, Python, uv, jq, shellcheck, ferramentas de rede e Zplug. Cada pacote instalado é ignorado nas execuções seguintes; falhas individuais de APT são registradas. **Atenção:** versões de Go/Node dos repositórios Debian podem ser mais antigas que as versões upstream. O Zplug é clonado, mas a ativação de plugins exige configuração no `~/.zshrc`. O script de Notify! é instalado separadamente, já como usuário normal.

### 🔔 Notify! na VM

Depois de entrar com `su - rod`:

```bash
curl -fsSL https://raw.githubusercontent.com/rodkisten/codespaces/main/notify/install.sh | bash
exec zsh
```

Configure `~/.config/rod-notify/config` com `ROD_NOTIFY_URL` e `ROD_NOTIFY_TOKEN` (veja a seção Rod Notify).


## 💜 Rod Prompt Neon: rounded + pontinhos full-width

Tema Zsh de duas linhas, com **pasta violeta**, **repositório e branch ciano**, **status verde ou coral** e separador `······` dimmed até a largura do terminal. Sem Powerlevel10k, sem Nerd Fonts e sem `git status` pesado. Exibe código de saída do comando anterior.

```text
~/code/photointel · main ·····························
╰─ $ 
~/code/photointel · main ·····························
╰─ $ ✕ 127
```

**Debian:** `debian/install.sh` instala/atualiza automaticamente o tema e adiciona uma linha de `source` ao `~/.zshrc` existente. Reabra o Zsh com `exec zsh`. O arquivo é `~/.config/zsh/rod-prompt.zsh`.

**Codespaces:** o tema substitui o `rod-mobile` anterior e também é atualizado pelo `install.sh --shell --force` ou pelo instalador do devcontainer. Para instalar só o tema na VM já existente:

```bash
mkdir -p ~/.config/zsh
curl -fsSL https://raw.githubusercontent.com/rodkisten/codespaces/main/.devcontainer/zsh/rod-mobile.zsh-theme -o ~/.config/zsh/rod-prompt.zsh
grep -Fq 'source "$HOME/.config/zsh/rod-prompt.zsh"' ~/.zshrc || printf '\nsource "$HOME/.config/zsh/rod-prompt.zsh"\n' >> ~/.zshrc
exec zsh
```

Variáveis opcionais antes do `source`: `ROD_PROMPT_DOTS=0` (sem separador), `ROD_PROMPT_SHOW_BRANCH=0`, `ROD_PROMPT_SHOW_REPO=0`. O comprimento da linha acompanha `COLUMNS`, inclusive após redimensionamento. Nomes de diretórios com caracteres de largura especial podem apresentar pequenas diferenças visuais em terminais distintos.

## 🩺 Rod Zsh Doctor: recuperação de VPS

O diagnóstico usa `--check` sem alterar arquivos. O modo `--repair` faz backup do `~/.zshrc`, substitui apenas o prompt emergencial antigo e mantém o Rod Notify, seus tokens e o sender existentes.

```bash
curl -fsSLo /tmp/rod-zsh-doctor.sh https://raw.githubusercontent.com/rodkisten/codespaces/main/scripts/rod-zsh-doctor.sh
bash /tmp/rod-zsh-doctor.sh --check
bash /tmp/rod-zsh-doctor.sh --repair
exec zsh
```

Verifique erros e status com `command rod_missing_123; echo $?` (esperado: 127). O doctor não instala Zplug, Oh My Zsh ou outros plugins. **Não execute instaladores antigos do Relay enquanto houver erros de codificação.** O token deve permanecer em arquivo privado, nunca no GitHub ou no histórico.


## 💜 Rod Prompt Neon 2 · Zinit sem Oh My Zsh

O tema novo vive em `config/zsh/rod-prompt-neon.zsh` e as opções em `config/zsh/rod-prompt-neon.config.zsh`. O plugin `zsh-syntax-highlighting` é opcional: a renderização do prompt não depende dele.

Instalação recomendada no Codespaces atual (preserva seu `~/.zshrc`, com backup):

```bash
git clone --depth 1 https://github.com/rodkisten/codespaces.git /tmp/rod-codespaces
bash /tmp/rod-codespaces/scripts/install-rod-zinit.sh
exec zsh
```

O instalador instala o Zinit, copia o tema e configura o carregamento por uma única linha gerenciada. Em instalações seguintes, mantém o arquivo de preferências existente. Para atualizar, execute `git -C /tmp/rod-codespaces pull --ff-only` e rode novamente o instalador.

Edite `~/.config/zsh/rod-prompt-neon.config.zsh` para escolher `ROD_PROMPT_DIR_MODE`, `ROD_PROMPT_BRANCH_MODE`, `ROD_PROMPT_ERROR_POSITION`, `ROD_PROMPT_GIT_CACHE_TTL`, `ROD_PROMPT_GIT_SYNC_INTERVAL`, `ROD_PROMPT_GIT_FETCH`, ícones e cores. O fetch remoto é opt-in (padrão 0). Indicadores locais usam cache com TTL e podem causar uma breve consulta Git quando expiram.

**Atenção ao pacote gerado:** os fontes de `tools/installer.footer.sh` e `.devcontainer/` já usam Zinit + Neon, mas `install.sh` na raiz precisa ser regenerado com `bash tools/build-installer.sh` e versionado antes de usar o comando remoto. Até lá, prefira `scripts/install-rod-zinit.sh`. O modo padrão de devcontainer exige rebuild.

## 💜 Rod Zsh com Zinit (sem Oh My Zsh)

O Rod Zsh usa plugins Zinit (completions, autosuggestions, history-substring-search e syntax-highlighting), configurações de histórico, fzf, aliases e helpers de CLI. O Rod Prompt e o Rod Notify permanecem independentes. O instalador faz backup de `~/.zshrc` e não modifica o token do Relay.

```bash
git clone --depth 1 https://github.com/rodkisten/codespaces.git /tmp/rod-codespaces
bash /tmp/rod-codespaces/scripts/install-rod-zinit.sh
exec zsh
```

Para atualizar: `git -C /tmp/rod-codespaces pull --ff-only` e execute novamente o instalador. Antes de usar, confira `zsh -n ~/.zshrc`. Plugins que dependem de ferramentas externas só funcionam quando elas estão instaladas.

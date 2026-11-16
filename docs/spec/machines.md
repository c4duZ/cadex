# machines

## Para que serve
Usar as outras máquinas do dono como se fossem este Mac: ver quais estão no ar, abrir um terminal
nelas, mandar uma tarefa rodar lá, usar o Docker delas daqui e mostrar um servidor deste Mac no
celular. A rede é o Tailscale que o dono já tem (`docs/adr/0030-installed-tailscale.md`, plano
`docs/plans/23-machines.md`). Sem o Tailscale, nada disto aparece.

## Comportamento
### As máquinas da tailnet
- Com o Tailscale rodando, o Cadex lê a lista de máquinas da tailnet do dono pela API local do
  Tailscale. Acha o Tailscale sozinho: o `tailscaled` aberto, o app Standalone, o app da App Store
  ou, sem nenhum desses, a CLI `tailscale`. Nenhuma tela pede para instalar ou entrar.
- O app da App Store guarda o acesso numa pasta protegida: na primeira leitura, o macOS pergunta
  uma vez se o Cadex pode ler. Recusado, o Cadex usa a CLI, se houver; senão, o grupo não aparece.
- De cada máquina: o nome (o curto e o MagicDNS, `pc.<tailnet>.ts.net`), o IP 100.x, o sistema, o
  dono, online ou não, a última vez vista, e o caminho (direto, ou pelo relay e qual). Este Mac
  aparece como "this Mac" e não entra na contagem.
- A lista muda sozinha quando uma máquina entra, sai, liga ou desliga (o fluxo de mudanças do
  Tailscale). Se esse fluxo falhar, o Cadex relê a lista a cada 30 s, só enquanto o cartão ou a
  paleta mostram máquinas.

### No cartão do ssh
- O cartão do item SSH da barra de status (`docs/spec/ssh.md`) ganha, abaixo dos hosts do
  `~/.ssh/config`, o grupo "Tailnet" com as máquinas: a bolinha (verde online e direto, amarela
  online pelo relay, vermelha offline), o nome, o sistema e "direct 12 ms", "relay (sao) 80 ms" ou
  "offline, seen 3h ago".
- A latência vem do ping do Tailscale (pela API local, sem abrir processo; só com a CLI, um
  `tailscale ping`), uma vez por máquina online, ao abrir o cartão e no "Test Again"; nunca por
  relógio.
- O número do item ("SSH 3/3") conta os hosts do `~/.ssh/config`; as máquinas da tailnet têm a
  contagem delas no título do grupo ("Tailnet 2/3").
- Uma máquina que também é um host do `~/.ssh/config` (mesmo nome ou mesmo endereço) aparece nos
  dois grupos.

### Conectar
- Clicar numa máquina (ou machines.connect, que lista as máquinas online no ⌘K) abre uma aba com
  `ssh <usuário>@<máquina>.<tailnet>.ts.net`. Na primeira vez numa máquina, o Cadex pergunta o
  usuário (sugere o deste Mac) e lembra por máquina; machines.connect com ⌥ pergunta de novo.
- machines.ping mede a latência de uma máquina na hora; machines.refresh relê a lista;
  machines.copy-address copia o nome MagicDNS (com ⌥, o IP 100.x).
- O Cadex não lê chave ssh, senha nem tráfego: só abre o `ssh` do dono numa aba. Se o `ssh` pedir
  senha ou confirmar a chave do host, é no terminal, como sempre.

### Rodar em outra máquina (mínimo)
- Ver "Rodar em" em `docs/spec/worktrees.md`: a tarefa roda no remoto por ssh, e a sessão aparece
  em Agents como "em <máquina>" (`docs/adr/0031-run-on-remote.md`).

### Docker pela tailnet
- machines.docker-context numa máquina cria (se ainda não existir) o contexto do Docker
  `<máquina>` apontando para `ssh://<usuário>@<máquina>` e o escolhe **na aba com foco**: a aba
  ganha `DOCKER_CONTEXT=<máquina>` e o `docker` dela fala com o daemon de lá. Os outros terminais
  continuam no contexto de antes; o Cadex nunca roda `docker context use`.
- A barra de status mostra o contexto da aba com foco ("docker: pc"), quando há um.
- A aba ganha o contexto pelo shell dela: o Cadex digita `export DOCKER_CONTEXT='pc'` quando o
  shell está no prompt; com um programa rodando, abre uma aba nova para isso. "This Mac" digita
  `unset DOCKER_CONTEXT`. Um `unset` digitado à mão não é visto pelo Cadex: o item da barra de status
  continua mostrando o último que ele pôs.
- machines.docker-ps lista no ⌘K as máquinas e, escolhida uma, os contêineres dela (nome, imagem,
  estado): escolher um abre o shell dele numa aba (`docker exec -it <contêiner> bash`, `sh` se não
  houver bash), e cada porta publicada de um que roda tem a linha que a abre no preview
  (`http://<máquina>:<porta>`). (No ⌘K e não no cartão: o cartão do ssh é para conectar; o plano
  pedia o cartão da máquina, que não existe.)
- Um contêiner com o sidecar do Tailscale (`docs/adr/0032-workspace-recipes.md`) entra na tailnet
  com nome próprio e aparece como mais uma máquina, em até 30 s depois de subir.
- O PC Windows do dono, pelo Ubuntu do WSL (o Windows não entra; **ainda não testado no PC**):
  1. no Ubuntu, `curl -fsSL https://tailscale.com/install.sh | sh` e `sudo tailscale up` (entra com a
     conta do dono; o Ubuntu vira uma máquina própria da tailnet);
  2. `sudo apt install -y openssh-server` e `sudo service ssh start`; a chave do Mac em
     `~/.ssh/authorized_keys` do Ubuntu, para o ssh não pedir senha (o Cadex nunca pergunta senha);
  3. Docker: o Docker Desktop do Windows com a integração WSL ligada para esse Ubuntu, ou o
     `docker.io` do Ubuntu; `sudo usermod -aG docker $USER` e entrar de novo;
  4. com o systemd ligado no WSL (`/etc/wsl.conf`: `[boot]` e `systemd=true`, depois `wsl
     --shutdown`), o `tailscaled` e o `sshd` sobem sozinhos quando o WSL volta;
  5. conferir do Mac: `tailscale status` mostra o Ubuntu; `ssh <usuário>@<nome>.<tailnet>.ts.net`
     entra sem senha; `docker --context <nome> ps` lista.

### Ambiente descartável
- Ver "Ambiente descartável" em `docs/spec/worktrees.md`: a receita `.cadex/environment.toml` do
  repositório sobe um contêiner por tarefa, que suspende, retoma e é destruído com ela.

### Aceitar outras máquinas
- machines.acceptRemote (desligada): ligada, o Cadex escuta na porta 47100 **só no IP 100.x** deste Mac
  (nunca em todas as interfaces), para o `cadexd` e o celular que vêm depois. Cada conexão é
  conferida pelo Tailscale (WhoIs): só aparelhos do mesmo usuário da tailnet; os outros são
  fechados sem resposta. Desligada, nada escuta na rede.

### Compartilhar um servidor deste Mac
- Na barra da aba de preview, com o Tailscale ligado no Cadex, o botão de compartilhar abre um menu
  com "Share on Tailnet", "Share Publicly…" e "Stop Sharing…" (os mesmos comandos do ⌘K; o que não
  pode rodar agora fica apagado). "Share on Tailnet" (machines.share-port) roda `tailscale serve --bg --https=<porta> http://localhost:<porta do servidor>`
  na primeira de 443, 8443 e 10000 que o dono ainda não serve, e mostra o endereço
  `https://<este-mac>.<tailnet>.ts.net[:porta]/`, com copiar e abrir: abre no celular do dono, na
  tailnet. Só servidor deste Mac (localhost, 127.0.0.1, [::1]); outra página, o comando diz que não.
- "Stop Sharing" (machines.stop-sharing) desfaz o que o Cadex ligou, e só isso: um `serve` que o
  dono ligou por fora fica.
- "Share Publicly…" (machines.share-public, o Funnel, beta do Tailscale) só aparece se o Tailscale
  deixar e a porta for 443, 8443 ou 10000; pede confirmação dizendo que a porta fica aberta para a
  internet. Parar desfaz.

  A conexão aceita fala o mesmo protocolo do socket do app, com o token de uma sessão; o pedido do
  kit (que confia num processo deste Mac) nunca é aceito de fora.

### Notificações por máquina
- agents.mutedMachines lista este Mac, cada host do `~/.ssh/config` e cada máquina da tailnet;
  as notificações de uma máquina silenciada não aparecem; o sininho e o feed continuam
  (`docs/spec/agents.md`). agents.mute-machine liga e desliga cada uma no ⌘K; "Silenciar os agentes
  deste Mac" nas configurações é o mesmo para este Mac.

### Configurações
- machines.tailscale (ligada): desligada, nenhum socket do Tailscale aberto, nenhum arquivo dele
  lido e nenhum processo dele rodado; o grupo "Tailnet" e os comandos somem.
- machines.acceptRemote (desligada), acima.

## Estados
- **Sem Tailscale** (não instalado, parado ou desconectado): o grupo "Tailnet" não aparece e os
  comandos machines.* dizem "Tailscale is not running" na paleta. Nenhum erro, nenhum aviso.
- **Tailscale pedindo login**: o grupo diz "Tailscale needs you to log in" (o Cadex não abre o
  login).
- **Lendo**: o grupo mostra as máquinas da última leitura, com a bolinha cinza até a primeira
  resposta.
- **Só este Mac na tailnet**: o grupo diz "No other machines on your tailnet".
- **Leitura parcial** (uma versão do Tailscale sem algum campo): mostra o que leu e, no rodapé do
  cartão, "Some details could not be read from this Tailscale version".
- **machines.tailscale desligado**: como sem Tailscale.

## Casos de borda
- O Tailscale troca de jeito (do App Store para o Standalone, ou do `tailscaled`): o Cadex acha o
  novo na próxima leitura, sem reabrir o app.
- Máquina sem MagicDNS (desligado na tailnet): conecta pelo IP 100.x.
- Máquina compartilhada de outro usuário (nó compartilhado com o dono): aparece, marcada com o
  dono; nunca é aceita pelo machines.acceptRemote (WhoIs de outro usuário).
- Docker ausente nesta máquina: os comandos de Docker dizem "Docker is not installed" e param.
- Docker ausente na máquina remota, ou usuário fora do grupo `docker`: o erro do `docker` aparece
  como veio, no cartão.
- `tailscale serve` já ligado pelo dono na mesma porta: o Cadex mostra o endereço e não o desliga
  no "Stop Sharing".
- O Cadex fecha com um `serve` ligado por ele: continua ligado (o Tailscale guarda) e o Cadex
  lembra que foi ele, para o "Stop Sharing" de depois.

## Critérios de aceite
- [ ] Com o Tailscale do dono, as máquinas aparecem no cartão do ssh em até 2 s, com online e
      caminho iguais ao `tailscale status`; desligar o PC o marca offline.
- [ ] Sem Tailscale (daemon parado), o grupo some sem erro.
- [ ] As três variantes do Mac e a CLI lidas por testes com respostas gravadas (versão velha, campo
      faltando, JSON quebrado, sem daemon).
- [ ] Com machines.tailscale desligado, `fs_usage` e `nettop` não mostram o Cadex tocando o
      Tailscale.
- [ ] machines.connect abre a aba com `ssh <usuário>@<máquina>.<tailnet>.ts.net`, e o usuário é
      lembrado.
- [ ] Com o contexto do Ubuntu do WSL do PC na aba, `docker ps` lista os contêineres do PC; os
      outros terminais seguem no contexto de antes.
- [ ] Um contêiner com sidecar aparece como máquina em até 30 s, e o preview abre
      `http://<nome>:<porta>`.
- [ ] Com machines.acceptRemote desligada, nada escuta na tailnet (`lsof -i`); ligada, só no IP
      100.x, e uma conexão de outro usuário é recusada.
- [ ] O link ts.net abre a página no celular do dono; "Stop Sharing" deixa o `tailscale serve
      status` vazio; o Funnel só liga depois da confirmação.
- [ ] Notificações de uma máquina silenciada não aparecem.

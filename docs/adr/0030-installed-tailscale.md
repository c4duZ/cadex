# 0030 — O Tailscale instalado como a rede entre as máquinas do dono

Data: 2026-11-16 · Status: aceita · Revê em parte `docs/adr/0007-one-step-install.md` (uma feature
que depende de um programa que o Cadex não instala, opcional) · Plano `docs/plans/23-machines.md`

## Contexto
O dono quer usar as outras máquinas dele como se fossem este Mac: o PC de mesa, um Docker lá, um
Ubuntu num contêiner (o dono, 2026-11-14). Para isso o Cadex precisa saber quais máquinas existem,
se estão no ar, como chegar nelas e, quando uma delas falar com o Cadex, quem está do outro lado.

O dono já usa o Tailscale. Cada máquina da tailnet tem um nome (`pc.<tailnet>.ts.net`, o MagicDNS)
e um IP 100.x; o tráfego vai cifrado, direto entre as duas quando dá e por um relay quando não dá.
O daemon de cada máquina responde a uma API local, a **LocalAPI**: a lista de máquinas (status),
quem é o dono de um IP da tailnet (WhoIs, só aparelhos do mesmo usuário contam) e um fluxo de
mudanças (o "IPN bus").

No Mac, o Tailscale vem de três jeitos, e cada um expõe a LocalAPI num lugar diferente. Conferido
neste Mac em 2026-11-16, Tailscale 1.104.7, app Standalone (a extensão de sistema `macsys`):
- não há `/var/run/tailscaled.socket` (esse é o do `tailscaled` aberto, da instalação pelo
  Homebrew ou de código);
- `/Library/Tailscale/ipnport` é um link simbólico cujo destino é a porta (`51403`), e
  `/Library/Tailscale/sameuserproof-<porta>` guarda o token, com modo 0640, dono root e grupo admin
  (o usuário administrador lê, outro não);
- `http://127.0.0.1:<porta>/localapi/v0/status` com o token como senha (usuário vazio) responde
  200; sem o token, 401. `whois?addr=<ip>:<porta>` devolve `Node` e `UserProfile`;
  `watch-ipn-bus` fica aberto mandando as mudanças;
- o grupo compartilhado do app (`~/Library/Group Containers/…io.tailscale.shared`), onde o app da
  App Store deixa porta e token, está fechado para outro app sem a permissão do dono (o `ls` dá
  "Operation not permitted");
- `/usr/local/bin/tailscale` é um script de duas linhas que chama o binário de dentro do app.

A LocalAPI não é uma API pública com garantia: os campos mudam entre versões.

## Decisão
- **O Cadex usa o Tailscale que o dono instalou, e só ele.** Não embute, não instala, não pede
  para instalar. Sem Tailscale, nada desta parte aparece e nada dá erro: a feature `machines` fica
  vazia e as outras seguem iguais. Isso não fere a instalação em um passo (ADR 0007): o Cadex
  continua sem dependência; o Tailscale é do dono, como o `git` e o `docker`.
- **Acha o daemon nesta ordem**, parando no primeiro que responde:
  1. o socket do `tailscaled` aberto (`/var/run/tailscaled.socket`);
  2. o app Standalone: a porta pelo link `/Library/Tailscale/ipnport` e o token pelo
     `sameuserproof-<porta>`, falando com `127.0.0.1:<porta>`;
  3. o app da App Store: porta e token no grupo compartilhado do app. O macOS pede a permissão uma
     vez; vem depois do Standalone para quem tem o Standalone nunca ver o pedido;
  4. sem nenhum, a CLI: `tailscale status --json` (ou o binário de dentro do app com
     `TAILSCALE_BE_CLI=1`), lida de 30 em 30 s só com alguém olhando.
- **Lê pouco, e tolera a mudança.** Da LocalAPI, só o status (as máquinas: nome MagicDNS, IP
  100.x, sistema, dono, online, última vez visto, caminho direto ou relay), o WhoIs e o fluxo de
  mudanças. Campo que falta é pulado; JSON que não fecha vira "não li", nunca trava nem derruba
  nada; a página diz o que não conseguiu ler. Os testes usam respostas gravadas (versão velha,
  campo faltando, JSON quebrado, sem daemon).
- **Identidade por WhoIs, sem token do Cadex.** Quando outra máquina falar com o Cadex (ADR 0031,
  fase F do plano 23), o Cadex pergunta ao daemon quem é o IP do outro lado e só aceita aparelho
  do mesmo usuário da tailnet. Nada de chave própria, senha ou par de chaves para guardar.
- **Mudar a configuração do dono só por comando.** Ler é sempre seguro; `tailscale serve` e
  `tailscale funnel` só rodam por comando explícito, e o Cadex desfaz só o que ele mesmo ligou.
- **Desligável.** `machines.tailscale` (ligada). Desligada, nenhum socket aberto, nenhum arquivo
  do Tailscale lido, nenhum processo rodado.

## Alternativas recusadas
- **Embutir a libtailscale** (o Tailscale como biblioteca dentro do app): cerca de 20 MB a mais
  por arquitetura (medido em 2026-11-14), um runtime Go dentro do processo do Cadex, e um panic do
  Go derruba o app. Fica como opção futura, para quando o Cadex precisar de uma tailnet sem o app
  do Tailscale (o celular, talvez); propor isso é rever esta ADR.
- **Uma tailnet do Cadex para os usuários**, ou a marca Tailscale como se fosse nossa: os termos do
  Tailscale são de uso pessoal ou interno (https://tailscale.com/terms), e o dono não quer operar
  rede de ninguém.
- **Só a CLI**: um processo por leitura e nenhum aviso de mudança; fica como último recurso.
- **Ler o Group Container primeiro**: faria o macOS pedir permissão a quem tem o Standalone, sem
  necessidade.
- **mDNS, varredura da rede local ou lista de IPs à mão**: não atravessa redes, não diz quem é o
  dono do aparelho e pede configuração.

## Consequências
- Feature nova `machines`, só no app macOS (`docs/spec/machines.md`). O Windows fica para o port
  (lá a LocalAPI é um named pipe).
- O cartão do ssh ganha o grupo "Tailnet" pelo app; o ssh não importa `machines`.
- Uma atualização do Tailscale pode esconder um campo; a página diz e o resto segue. Conferir a
  LocalAPI a cada versão nova do Tailscale que o dono instalar.
- Embutir a libtailscale, operar uma tailnet para os usuários ou mudar a configuração do Tailscale
  do dono sem comando é desfazer esta decisão.

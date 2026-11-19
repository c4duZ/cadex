# Plano 39 — Os terminais do Cadex pelo telefone

Do telefone, pela tailnet do dono e por SSH no Mac, entrar nas abas que estão abertas no Cadex, abrir
sessões novas que nascem no Cadex do Mac e ver no Safari os HTML que o agente fez. O dono pediu em
2026-11-19 ("quero abrir terminais no cadex e ver os terminais que estão abertos no cadex"; "eu
quero poder abrir uma sessão num projeto por lá"; "um HTML pode ser"; "pode só fazer").

## O que eu quero
- A aba aberta no Mac aparece igual no telefone, ao vivo, com a tela de antes; o que se digita num
  lado chega no outro. É o mesmo processo: o mesmo Claude, a memória, os hooks, a conta.
- Abrir pelo telefone um terminal ou o Claude num projeto, e a aba estar no Cadex do Mac também.
- Um HTML (ou PDF) feito pelo agente aberto no Safari do telefone, funcionando, e que dá para baixar.
- Tudo pelo app de terminal que o dono já tem no telefone (Termius, Blink), sem app nosso.

## O que eu não quero
- Mandar imagem do telefone (o dono tirou, 2026-11-19).
- Nada escutando fora da tailnet: nem internet, nem a rede local.
- O telefone tomar a aba do Mac (o attach de hoje faz isso: "the newest app wins").
- Um segundo jeito de abrir aba: o `cadex new` roda o comando registrado, como um clique.
- Mudar a interface do Mac além de uma marca na aba com alguém de fora conectado.

## Como eu quero
- [ ] A. Duas telas na mesma sessão: o daemon (`core/features/terminal/daemon_handle.zig`,
  `core/features/terminal/daemon_state.zig`) guarda vários clientes por sessão em vez de um, manda a saída a todos e cada um
  escreve no master. O tamanho do pty é o menor entre os clientes, e volta ao do Mac quando o de
  fora sai (como o tmux). O app sabe quantos de fora há (para a marca na aba). Hoje quem lê o pty é
  só o daemon e o app recebe o master só para escrever e redimensionar (`core/features/terminal/daemon_client.zig`): a
  saída já passa pelo daemon, o que muda é a lista de clientes e quem decide o tamanho.
  Testes em `core/features/terminal/daemon_test.zig`: dois clientes veem a mesma saída, os dois digitam, o tamanho menor
  vale e volta, um sai e o outro segue, o app religando não derruba o de fora.
- [ ] B. `cadex attach`: no programa `cadex` (`core/features/agent-tools/`), um cliente do daemon
  que põe o terminal em modo cru, lista as sessões (projeto, nome da aba, se tem agente) e entra
  numa com o replay; a saída vai direto ao terminal de quem chamou (quem desenha é o app do
  telefone); ao mudar de tamanho, avisa o daemon. Uma tecla (Ctrl+\ e depois d, como o tmux) sai sem
  fechar a sessão. Os nomes das abas e projetos vêm do app pelo socket dele; com o app fechado, só
  os ids.
- [ ] C. `cadex new <projeto> [claude]` (o `cadex open` já abre um arquivo): pede ao app, pelo socket que o `cadex` já usa, o comando
  registrado que abre uma aba no projeto (um terminal, ou o Claude pelo kit, com memória e hooks); o
  app devolve o id da sessão e o `cadex` entra nela como na B. Com o app fechado, o `cadex` o abre e
  espera o socket. Fora de uma sessão do Cadex não há token: o comando vale só para o dono no SSH
  (mesmo usuário do Mac), e a lista do que pode é curta (abrir aba, listar).
- [ ] D. O menu: `cadex` sem argumentos, num terminal que não é uma aba do Cadex, mostra os
  projetos e as abas numerados; um número entra, `n` abre um terminal no projeto escolhido, `c` abre
  o Claude. Feito para teclado de telefone: uma tecla por escolha, nada de digitar nome.
- [ ] E. `cadex share <arquivo>`: o app serve o arquivo num endereço da tailnet (só o IP do
  Tailscale, achado pela feature machines) e o `cadex` imprime o link; o Safari do telefone abre a
  página e baixa. Uma pasta de HTML leva junto o que a página carrega (CSS, imagens vizinhas). O
  link expira (uma hora) e tem um token no caminho. Sem Tailscale, o comando diz isso e sai.
- [ ] F. O guia do dono em docs/guides/phone.md (novo): Tailscale no Mac e no telefone, Login Remoto
  no Mac, o app de terminal com mosh, e os comandos `cadex`, `cadex attach`, `cadex new`, `cadex
  share`.

Ordem: A, B, C, D (o caminho principal); E é independente e pode vir antes. A fase A mexe no
terminal: pede o `make perf`, que só roda quando o dono pedir.

## Como validar
- `make check` ao fim de cada fase.
- A: os testes de dois clientes no `core/features/terminal/daemon_test.zig`.
- B, C, D: o `cadex` contra uma instância de teste do app (o socket curto em `$TMPDIR`).
- E: o link aberto por `curl` pelo IP da tailnet funciona e pelo 127.0.0.1 e pelo IP da rede
  local não.
- No fim, o dono no telefone: entra numa aba com o Claude aberto no Mac, digita, vê no Mac; abre
  uma sessão nova por lá e a vê no Mac; abre um HTML no Safari.

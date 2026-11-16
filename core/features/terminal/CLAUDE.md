# terminal (núcleo)

## O que eu quero
- Abrir, redimensionar e fechar sessões de shell num PTY, com o shell de login do usuário.
- Alimentar a libghostty-vt com a saída e expor ao app o que ele precisa desenhar.
- Integração de shell (OSC 7) para saber o diretório atual de cada sessão.
- Saber se uma sessão tem um processo rodando em primeiro plano (para avisar antes de fechar) e o
  grupo de processos dele (`cadex_terminal_foreground_group`: o app liga a sessão de um agente ao
  terminal onde ela roda; 0 no Windows por enquanto) e o pid do shell (`cadex_terminal_shell_pid`:
  o app reconhece um `cadex claude` digitado num terminal dele, plano 22 fase C).

## O que eu não quero
- Qualquer outra feature, do núcleo ou do app, falando direto com a libghostty: só `model.zig`,
  `render.zig`, `input.zig`, `selection.zig`, `paste.zig`, `search.zig`,
  `links.zig` e `mouse.zig`.
- Processo do shell sobrevivendo ao fechamento da sessão.
- Callback do app chamando `cadex_terminal_close`: o close espera a thread de leitura, que é quem
  chama o callback (trava).
- Devolver ao app ponteiro que não veio do malloc (fatia vazia do Zig): ver
  `c_api.zig:cadex_terminal_copy_text`.

## Como eu quero
- Porta de entrada: `terminal.zig`. API C: `c_api.zig`, declarada em `../../include/cadex.h`.
- `model.zig`: libghostty-vt (Terminal + TerminalStream); respostas ao programa por callback.
  Liga o agrupamento de grafemas (modo 2027), senão emoji com tom de pele vira dois glifos.
- `render.zig`: traduz o RenderState num quadro plano (cores RGB, texto UTF-8, flags). Campos
  `style` e `grapheme` do RenderState só valem em certas células: ver `render.zig:translateCell`.
- `input.zig`: teclas (Key e Mods nossos, CADEX_KEY_* e CADEX_MOD_*) codificadas pelo encoder da
  libghostty com os modos atuais do terminal (setas em modo de aplicação, kitty). Lê os modos com a
  sessão travada (`session.zig:key`). Alt só chega quando o app trata o Option como Meta.
- `selection.zig`: seleção pelo SelectionGesture da libghostty (clique, arrasto com autoscroll,
  Shift+clique, tudo) e o texto selecionado, sem espaços no fim e com linhas quebradas por largura
  juntas. O app conta os cliques (clickCount); o gesto nunca conta sozinho. Mora no `model.zig`.
- `paste.zig`: colagem codificada para o programa (bracketed paste; sem ele, \n vira Enter; bytes
  de controle viram espaço), se a colagem é segura e o escape de caminhos para o shell (aspas
  simples quando precisa). O que colar (arquivos, imagem, texto) é decisão do app.
- `search.zig`: busca (⌘F) pela TerminalSearch da libghostty, na tela e no histórico; marca as
  ocorrências no quadro pelos destaques do RenderState. Alcança a saída nova a cada captura.
- `links.zig` + `link_detect.zig`: link sob a célula. Primeiro o hiperlink OSC 8; senão URL ou
  caminho achado no texto do quadro (linhas quebradas por largura juntas). Caminho só vale se
  existe: relativo resolve pelo OSC 7 ou pelo diretório do processo em primeiro plano
  (`pty_posix.zig:currentDirectory`; no Windows só o OSC 7).
- `mouse.zig`: mouse para programas que pedem (vim, htop, tmux) no formato que pediram; a roda vira
  relatório de botão, setas na tela alternativa (modo 1007) ou rolagem do histórico; foco (1004).
- Preferências: cursor padrão e piscar (`model.zig:setCursorDefaults`, o que o programa escolheu
  continua até ele resetar) e linhas de histórico ao abrir (`model.zig:createWithHistory`, até 100 mil).
- Cores do tema: `model.zig:setColors` troca o padrão de fundo, texto, cursor e das 16 ANSI; o que o
  programa trocou por OSC continua, e as consultas OSC 10/11/4 respondem com essas cores.
- Notificação de programa (OSC 777, OSC 9): o efeito desktop_notification da libghostty, ligado no
  `model.zig`, chega ao app pelo callback on_notification com título e texto já cortados e
  terminados em NUL (`program_notice.zig`).
- Título (OSC 0/2) e sino chegam ao app pelos callbacks on_title e on_bell (`model.zig:Notice`),
  na thread de leitura, como on_output.
- O estado de um agente pelo OSC 7501 (plano 19, `../../../docs/adr/0022-terminal-daemon.md`): o
  efeito program_status da libghostty, ligado no `model.zig`, responde à pergunta do programa e
  entrega cada relatório; só o registro principal (sem id) fica, nos tipos de `agent_status.zig`.
  Chega ao app pelo callback on_agent_status e por `cadex_terminal_agent_status` (estado, tipo e o
  texto já decodificado). Testado com o Claude Code de verdade em 2026-11-15: idle, working com a
  frase, blocked com "approve Bash: …".
- `local_url.zig`: endereços de servidor local na saída (localhost, 127.0.0.1, 0.0.0.0, [::1], com ou
  sem http://), sem sequências de escape (o Vite pinta a porta no meio do endereço), achados mesmo
  partidos entre duas leituras, uma vez por sessão; chegam ao app pelo callback on_local_url
  (docs/spec/preview.md). Com `http://` escrito, também um nome que pode ser de uma máquina da
  tailnet (plano 23): uma parte só (`ubuntu-dev`), `*.ts.net` ou 100.64/10; o app só oferece os
  nomes de máquinas que ele conhece.
- `session_view.zig` e `c_api_view.zig`: rolagem, seleção, busca e links da sessão, separados para
  `session.zig` e `c_api.zig` ficarem abaixo de 300 linhas.
- Rolagem e histórico no `model.zig`: pelo menos 10 mil linhas (limite em linhas com folga de uma
  página, porque a libghostty descarta páginas inteiras). Digitar ou colar limpa a seleção e volta
  ao fim (`session.zig:returnToInput`).
- `pty.zig`: a interface do PTY, um `Child` com os mesmos métodos nos dois sistemas.
  `pty_posix.zig`: forkpty + execve; o filho só faz chdir e execve (depois do fork, só chamadas
  seguras); espera, desliga (SIGHUP) e mata o filho. `pty_windows.zig`: ConPTY, shell (pwsh, senão
  Windows PowerShell) num Job Object; uma thread espera o processo e fecha o console, porque o
  ConPTY não fecha a saída sozinho quando o shell sai.
- `shell_env.zig`: shell, argv de login e ambiente (TERM=xterm-256color, TERM_PROGRAM=Cadex). A
  integração do zsh (plano 22, fase C; `../../../docs/spec/terminal.md`): com o shell `zsh` e
  CADEX_ZSH_INTEGRATION=<pasta> no ambiente (o app o põe no dele ao abrir), `ZDOTDIR=<pasta>` e o
  `ZDOTDIR` que havia vai em CADEX_USER_ZDOTDIR (`zshIntegration`); bash e fish ficam como estão. Vale
  para o PTY próprio e para o daemon, que abre os shells com o mesmo `pty_posix.zig`.
- `shell_windows.zig`: a linha de comando do shell no Windows. PowerShell aberto sem argumentos
  ganha a integração de shell (-NoExit -EncodedCommand, depois do $PROFILE do usuário): avisa a
  pasta por OSC 7 pelo LocationChangedAction do PowerShell 7, sem mexer no prompt; no Windows
  PowerShell sem esse gancho, embrulha o prompt. `links.zig:windowsDirectory` traduz o aviso
  (/C:/x vira C:\x).
- `session.zig`: thread de leitura e mutex (`core/shared/sync.zig`) protegendo o modelo. O close
  pede ao Child para destravar a leitura (no Mac o poll acorda a cada 50 ms; no Windows fecha o
  console), espera a thread e encerra o shell (Mac: SIGHUP e, depois de 200 ms, SIGKILL; Windows:
  o Job Object inteiro).
- O daemon do terminal (plano 19 fase E1, `../../../docs/adr/0022-terminal-daemon.md`), só no Mac,
  sem a libghostty: `daemon_main.zig` é o programa `cadex-terminald` (raiz em
  `../../cadex_terminal_daemon.zig`); `daemon.zig` o laço (um `poll`, SIGCHLD por pipe, sai sem
  sessão nem app); `daemon_handle.zig` cada frame do app (hello com versão, open, attach, list,
  close); `daemon_state.zig` sessões e conexões; `daemon_wire.zig` os frames e a passagem do master
  (SCM_RIGHTS); `daemon_ring.zig` a saída crua guardada (2 MiB); `daemon_modes.zig` os modos lidos da
  saída para depois do replay; `daemon_client.zig` o lado do app (testes agora, a sessão na E2).
- Spec em `../../../docs/spec/terminal.md`. Status: sessão, PTY, quadro para desenhar, teclas pelo
  núcleo, rolagem, seleção, colagem, busca, links, mouse
  para programas, foco, título, sino e API C prontos. Reflow ao redimensionar coberto por teste.

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- `session_test.zig` abre shells de verdade; `c_api_test.zig` usa a API C como o app usa.
- `selection_test.zig` cobre palavra, linha, arrasto, Shift+clique, tudo, linha quebrada por largura
  e as células marcadas no quadro; `model.zig` testa rolagem e as 10 mil linhas.
- `search_test.zig` e `links_test.zig` cobrem busca no histórico e links (URL quebrada em duas
  linhas, caminho relativo, OSC 8).
- `input.zig` testa setas em modo de aplicação, F-keys, modificadores, Ctrl/Meta e kitty.
- `render_test.zig` cobre cores, estilos, inversão, largura dupla, emoji e cursor.
- `shell_env.zig` testa a integração do zsh: zsh com e sem `ZDOTDIR` do dono, bash, fish e a pasta
  vazia.
- `daemon_test.zig`: o daemon numa thread com shells de verdade: a sessão sobrevive ao app, religa
  com o replay, termina sem app e guarda o código, close mata o shell, o segundo daemon e a versão
  errada são recusados, e o daemon sai sozinho sem sessão nem app.

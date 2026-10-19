# terminal (núcleo)

## O que eu quero
- Abrir, redimensionar e fechar sessões de shell num PTY, com o shell de login do usuário.
- Alimentar a libghostty-vt com a saída e expor ao app o que ele precisa desenhar.
- Integração de shell (OSC 7) para saber o diretório atual de cada sessão.
- Saber se uma sessão tem um processo rodando em primeiro plano (para avisar antes de fechar).

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
  (`pty.zig:currentDirectory`).
- `mouse.zig`: mouse para programas que pedem (vim, htop, tmux) no formato que pediram; a roda vira
  relatório de botão, setas na tela alternativa (modo 1007) ou rolagem do histórico; foco (1004).
- Preferências: cursor padrão e piscar (`model.zig:setCursorDefaults`, o que o programa escolheu
  continua até ele resetar) e linhas de histórico ao abrir (`model.zig:createWithHistory`, até 100 mil).
- Cores do tema: `model.zig:setColors` troca o padrão de fundo, texto, cursor e das 16 ANSI; o que o
  programa trocou por OSC continua, e as consultas OSC 10/11/4 respondem com essas cores.
- Título (OSC 0/2) e sino chegam ao app pelos callbacks on_title e on_bell (`model.zig:Notice`),
  na thread de leitura, como on_output.
- `local_url.zig`: endereços de servidor local na saída (localhost, 127.0.0.1, 0.0.0.0, [::1], com ou
  sem http://), sem sequências de escape (o Vite pinta a porta no meio do endereço), achados mesmo
  partidos entre duas leituras, uma vez por sessão; chegam ao app pelo callback on_local_url
  (docs/spec/preview.md).
- `session_view.zig` e `c_api_view.zig`: rolagem, seleção, busca e links da sessão, separados para
  `session.zig` e `c_api.zig` ficarem abaixo de 300 linhas.
- Rolagem e histórico no `model.zig`: pelo menos 10 mil linhas (limite em linhas com folga de uma
  página, porque a libghostty descarta páginas inteiras). Digitar ou colar limpa a seleção e volta
  ao fim (`session.zig:returnToInput`).
- `pty.zig`: forkpty + execve; o filho só faz chdir e execve (depois do fork, só chamadas seguras).
  Também espera, desliga (SIGHUP) e mata o filho.
- `shell_env.zig`: shell, argv de login e ambiente (TERM=xterm-256color, TERM_PROGRAM=Cadex).
- `session.zig`: thread de leitura com poll (acorda a cada 50 ms para ver se houve close) e mutex
  da libc protegendo o modelo; o close manda SIGHUP e, depois de 200 ms, SIGKILL.
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

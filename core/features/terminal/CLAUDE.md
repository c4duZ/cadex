# terminal (núcleo)

## O que eu quero
- Abrir, redimensionar e fechar sessões de shell num PTY, com o shell de login do usuário.
- Alimentar a libghostty-vt com a saída e expor ao app o que ele precisa desenhar.
- Integração de shell (OSC 7) para saber o diretório atual de cada sessão.
- Saber se uma sessão tem um processo rodando em primeiro plano (para avisar antes de fechar).

## O que eu não quero
- Qualquer outra feature, do núcleo ou do app, falando direto com a libghostty: só `model.zig` e `render.zig`.
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
- `pty.zig`: forkpty + execve; o filho só faz chdir e execve (depois do fork, só chamadas seguras).
- `shell_env.zig`: shell, argv de login e ambiente (TERM=xterm-256color, TERM_PROGRAM=Cadex).
- `session.zig`: thread de leitura com poll (acorda a cada 50 ms para ver se houve close) e mutex
  da libc protegendo o modelo; o close manda SIGHUP e, depois de 200 ms, SIGKILL.
- Spec em `../../../docs/spec/terminal.md`. Status: sessão, PTY, quadro para desenhar e API C prontos.

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- `session_test.zig` abre shells de verdade; `c_api_test.zig` usa a API C como o app usa.
- `render_test.zig` cobre cores, estilos, inversão, largura dupla, emoji e cursor.

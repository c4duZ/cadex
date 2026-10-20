# command-palette (app Windows)

## O que eu quero
- O registro de todos os comandos (ADR 0005) e a paleta que acha e executa qualquer um, igual à do
  Mac: seções com o campo vazio ("Abrir" primeiro), fuzzy do núcleo, prefixos `>` `/` `#` `@`.
- Os mesmos ids de comando do Mac (`../../../macos/features/command-palette/CLAUDE.md`).

## O que eu não quero
- Ação que só existe num botão, menu ou atalho: tudo passa por `registry.zig:run`.
- Comando indisponível aparecendo na paleta.
- Executar o escolhido no meio do quadro: a paleta guarda (`palette.zig:takePending`) e o app executa
  depois, com ela já fechada.

## Como eu quero
- Porta de entrada: `command_palette.zig`. `registry.zig`: Command (id, título, palavras-chave,
  atalho padrão na notação do Mac, `run` e `available`), Registry (add, find, run, recentes) e as
  seções por prefixo do id, na ordem da spec.
- `source.zig`: o que uma lista da paleta implementa (Source: search no arena do quadro, choose com
  Enter, Alt+Enter ao lado ou Ctrl+Enter em nova aba) e `rank`, o fuzzy do núcleo pela API C.
- `commands.zig`: os comandos como lista (Abrir, Recentes, seções; digitando, título e depois
  palavras-chave). O rótulo do atalho vem de quem monta (a feature shortcuts, pelo app).
- `palette.zig`: a caixa no topo, campo, linhas com títulos de seção, rodapé com as teclas, fecha
  ao clicar fora ou com Esc; a mesma lista de novo fecha, outra troca.
- Spec: `../../../../docs/spec/command-palette.md`.

## Como validar
- `make windows-app` compila os testes (cadex-command-palette-tests.exe); rodam na VM.

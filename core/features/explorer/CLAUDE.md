# explorer (núcleo)

## O que eu quero
- Listar, ler, escrever, criar, renomear, mover, copiar e apagar arquivos e pastas.
- Avisar o app quando algo muda no disco (FSEvents no macOS).
- Detectar arquivo binário ou grande demais antes de entregar o conteúdo.

## O que eu não quero
- Operação fora de um diretório autorizado (feature workspace).
- Seguir link simbólico para fora do workspace sem checar.
- Ler arquivo inteiro na memória sem limite.

## Como eu quero
- Toda operação passa pela checagem de diretório autorizado da feature workspace e usa o caminho
  canônico que ela devolve. Operação sobre a própria entrada (renomear, mover, copiar) não segue o
  link simbólico do último componente; ler e listar seguem, e o destino tem que estar dentro.
- Porta de entrada: `explorer.zig`. `listing.zig` lista uma pasta (pastas primeiro, ordem natural
  de `natural.zig`, `.git` fora); `operations.zig` cria, renomeia (`renamex_np` com RENAME_EXCL:
  nome ocupado é recusado sem corrida), move e copia (`copyfile` recursivo, clone no APFS, nome
  "x cópia.ext"); `read.zig` lê texto com limite (10 MB) e recusa binário (byte nulo nos primeiros
  8 KB, como o git); `watch.zig` observa com FSEvents numa fila própria, uma chamada por lote com
  cada pasta uma vez, e nenhuma chamada depois de stop(); `errors.zig` traduz o errno.
- Apagar não mora aqui: vai para a Lixeira do sistema pelo app (FileManager.trashItem).
- API C em `c_api.zig` e `c_api_watch.zig`. O link com CoreServices (FSEvents) está em
  `core/build.zig` (testes) e no `apps/macos/shared/core-bridge/module.modulemap` (app).
- A listagem marca o que .gitignore, .ignore e .git/info/exclude deixam de fora
  (`core/shared/ignore.zig`, com as regras do workspace a que a pasta pertence).
- Spec: `docs/spec/explorer.md`. Status: núcleo pronto (plano 4, fases B e D).

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- Teste que tenta escrever fora do workspace e recebe recusa; os testes usam pastas temporárias de
  `core/shared/test_dir.zig`. O teste de `watch.zig` usa FSEvents de verdade (leva ~0,3 s).

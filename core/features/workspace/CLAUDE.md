# workspace (núcleo)

## O que eu quero
- Saber quais diretórios o usuário autorizou e recusar operações fora deles.
- Diretório de lançamento (pasta passada ao abrir o app pela linha de comando).
- Ambiente de execução: local ou distro WSL (Windows).

## O que eu não quero
- Diretório autorizado por engano por causa de link simbólico ou caminho relativo.

## Como eu quero
- Caminhos sempre canonicalizados antes de comparar (realpath; caminho que ainda não existe resolve
  pela pasta pai) e comparados por componente: `/work` não contém `/workshop`.
- Porta de entrada: `workspace.zig` (`registry()`, o registro único do processo, usado pela API C,
  pelo explorer e pela busca). `paths.zig` canonicaliza e compara; `authorized.zig` guarda os
  diretórios autorizados (só cresce enquanto o app está aberto, com mutex porque busca e observação
  rodam em outras threads); `launch.zig` acha a pasta passada na linha de comando.
- Quem opera em arquivo usa o caminho que Registry.resolve devolve, não o que recebeu.
- API C em `c_api.zig`: `cadex_workspace_authorize`, `_is_authorized`, `_authorize_terminal`,
  `_launch_directory`. Erros: CADEX_NOT_FOUND e CADEX_NOT_AUTHORIZED (`core/status.zig`).
- Spec: `docs/spec/workspace.md`. Status: núcleo pronto (plano 4, fase A); WSL fica para o Windows.

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- Teste de recusa com link simbólico, com ../ apontando para fora e com pasta irmã de mesmo prefixo
  (`authorized.zig`).

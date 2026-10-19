# workspace (núcleo)

## O que eu quero
- Saber quais diretórios o usuário autorizou e recusar operações fora deles.
- Diretório de lançamento (pasta passada ao abrir o app pela linha de comando).
- Ambiente de execução: local ou distro WSL (Windows).

## O que eu não quero
- Diretório autorizado por engano por causa de link simbólico ou caminho relativo.

## Como eu quero
- Caminhos sempre canonicalizados antes de comparar.
- Spec de comportamento em docs/spec/workspace.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- Teste de recusa com link simbólico e com ../ apontando para fora.

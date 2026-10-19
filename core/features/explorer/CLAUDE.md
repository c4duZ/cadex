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
- Toda operação passa pela checagem de diretório autorizado da feature workspace.
- Apagar vai para a lixeira do sistema quando possível.
- Spec de comportamento em docs/spec/explorer.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- Teste que tenta escrever fora do workspace e recebe recusa.

# command-history (núcleo)

## O que eu quero
- Guardar os comandos executados no terminal em blocos e sugerir comandos ao digitar.

## O que eu não quero
- Gravar comando que começa com espaço (convenção dos shells para não salvar).

## Como eu quero
- Armazenamento local, com limite de tamanho.
- Spec de comportamento em docs/spec/command-history.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.

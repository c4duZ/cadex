# core/shared — compartilhado do núcleo

## O que eu quero
- Só o que 2 ou mais features do núcleo usam: processos, caminhos, erros, alocação.

## O que eu não quero
- Código de uma feature só morando aqui "porque pode ser útil".

## Como eu quero
- Antes de mover algo para cá, as duas features que usam têm que existir.

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.

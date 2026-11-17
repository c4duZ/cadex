# apps/macos/shared — compartilhado do app

## O que eu quero
- Só o que 2 ou mais features do app usam: componentes visuais, tokens de tema, a ponte com a API C.

## O que eu não quero
- Código de uma feature só morando aqui "porque pode ser útil".

## Como eu quero
- Antes de mover algo para cá, as duas features que usam têm que existir. Exceção decidida no
  plano 18: `session-kit/`, a porta que os planos 19 a 24 vão usar (o `CLAUDE.md` dela explica);
  plano 25: `state-glyph/`, o sinal de estado que as abas usam já e a árvore, o sino, o ⌘J e o
  quadro usam nos planos 26 a 30.

## Como validar
- `make macos-test` passa.

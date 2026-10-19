# apps/macos/shared — compartilhado do app

## O que eu quero
- Só o que 2 ou mais features do app usam: componentes visuais, tokens de tema, a ponte com a API C.

## O que eu não quero
- Código de uma feature só morando aqui "porque pode ser útil".

## Como eu quero
- Antes de mover algo para cá, as duas features que usam têm que existir.

## Como validar
- `make macos-test` passa.

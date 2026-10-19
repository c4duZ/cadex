# editor (app macOS)

## O que eu quero
- Editor de código com destaque de sintaxe para as linguagens comuns, modo vim e formatar ao salvar.
- Abrir arquivo grande sem travar; avisar quando é binário.

## O que eu não quero
- Escolher o componente de editor sem ADR: é o maior risco do projeto.

## Como eu quero
- Componente de editor decidido em um ADR antes da primeira linha.
- Spec de comportamento em docs/spec/editor.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make macos-test` passa.

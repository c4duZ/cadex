# source-control (app macOS)

## O que eu quero
- Painel com mudanças, stage por arquivo, commit (Cmd+Enter), push e pull, troca de branch.
- Diff lado a lado ou unificado.

## O que eu não quero
- Ação destrutiva sem confirmação.

## Como eu quero
- Usa a feature source-control do núcleo.
- Spec de comportamento em docs/spec/source-control.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make macos-test` passa.

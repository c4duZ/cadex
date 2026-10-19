# language-server (app macOS)

## O que eu quero
- Diagnósticos, ir para definição, autocomplete e formatação no editor, vindos do language server.

## O que eu não quero
- Editor travando à espera do language server.

## Como eu quero
- Usa a feature language-server do núcleo.
- Spec de comportamento em docs/spec/language-server.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make macos-test` passa.

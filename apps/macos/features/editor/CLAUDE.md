# editor (app macOS)

## O que eu quero
- Ler código: números de linha, setinha de dobrar, destaque de sintaxe e linha atual destacada.
- Edições pequenas, com o que o NSTextView já dá (digitar, desfazer, buscar).
- Abrir arquivo grande sem travar; avisar quando é binário.

## O que eu não quero
- Biblioteca de editor de terceiros, language server, autocomplete de código, vim ou formatar ao
  salvar (`../../../../docs/adr/0006-editor-reads-code-edits-markdown.md`).
- Recolorir o arquivo inteiro a cada tecla.

## Como eu quero
- NSTextView (TextKit 2) com uma régua de números de linha e dobras.
- Cores e dobras vêm da feature editor do núcleo; o app só pinta.
- A inteligência de Markdown (autocomplete, ⌘+clique, links quebrados, quem aponta pra cá) vem da
  feature markdown, pela porta de entrada dela.
- Spec de comportamento em docs/spec/editor.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make macos-test` passa.

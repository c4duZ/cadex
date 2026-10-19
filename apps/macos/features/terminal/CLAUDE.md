# terminal (app macOS)

## O que eu quero
- Desenhar o terminal em Metal, com fonte, cursor, seleção, links e true color.
- Teclado completo, colagem (texto, caminhos de arquivo e imagem como arquivo temporário), arrastar arquivos.
- Busca dentro do terminal e o modo em blocos com campo de comando estilo editor.

## O que eu não quero
- Lógica de terminal no app: o estado vem do núcleo.
- Redesenhar a tela inteira quando só uma linha mudou.

## Como eu quero
- Só desenha e repassa entrada; fala com a feature terminal do núcleo.
- Spec de comportamento em docs/spec/terminal.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make macos-test` passa.

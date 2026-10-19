# markdown (app macOS)

## O que eu quero
- Markdown renderizado com GitHub Flavored Markdown, alternando com o texto.
- Editando Markdown: autocomplete de caminho ao digitar `](`, de título depois de `#` e de nota ao
  digitar `[[`.
- ⌘+clique num link abre o arquivo no título certo; link quebrado sublinhado.
- Painel "quem aponta pra cá" com os arquivos que linkam o arquivo atual.

## O que eu não quero
- HTML do arquivo executando script.
- Sugestão atrasando a digitação.

## Como eu quero
- Respostas vêm da feature markdown do núcleo; esta feature só mostra (lista de sugestões,
  sublinhado, painel) e se liga ao editor pela porta de entrada dele.
- Abrir link, alternar texto e renderizado e mostrar "quem aponta pra cá" são comandos registrados.
- Conteúdo sanitizado antes de exibir.
- Spec de comportamento em docs/spec/markdown.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make macos-test` passa.

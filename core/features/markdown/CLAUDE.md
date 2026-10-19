# markdown (núcleo)

## O que eu quero
- Índice dos arquivos Markdown do workspace: títulos, links, links estilo wiki (`[[nota]]`) e de onde vem cada
  link.
- Respostas para o app: sugestões de caminho, de título e de nota wiki; destino de um link; links
  quebrados de um arquivo; quem aponta para um arquivo.

## O que eu não quero
- Language server ou processo externo (`../../../docs/adr/0006-editor-reads-code-edits-markdown.md`).
- Reindexar o workspace inteiro a cada arquivo salvo: só o arquivo que mudou.

## Como eu quero
- Porta de entrada: `markdown.zig`.
- Renderizado (`../../../docs/adr/0010-markdown-rendering.md`): `html.zig` escreve o HTML a partir dos
  eventos do md4c (âncoras do GitHub por `anchor.zig`, `[[nota]]` vira href cadex-wiki:, código
  colorido por `code_html.zig` com o tree-sitter da feature editor, HTML embutido por
  `sanitize.zig`, que tira script, style, iframe, on* e javascript:).
- Índice: `outline.zig` lê títulos e links com posição pelo tree-sitter de Markdown (pela porta de
  entrada da feature editor); `[[wiki]]`, que a gramática não conhece, por varredura fora de código.
  Os textos vão para a arena do outline (o índice libera o arquivo lido). `resolve.zig`: caminho
  relativo à nota (ou à raiz com `/`), nota wiki mais próxima, título pela âncora. `index.zig`: as
  notas do workspace numa thread, seguindo o watcher do explorer pasta por pasta (o caminhante é o
  da busca, pela porta de entrada dela). `queries.zig`: links de um texto não salvo com quebrados
  marcados, quem aponta pra cá, para onde vai um destino.
- API C em `c_api.zig`: respostas em linhas com campos separados por tab; offsets de links em UTF-16.
- Spec: `docs/spec/markdown.md`. Status: núcleo pronto (plano 5, fase C).

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- Teste com uma pasta de exemplo (`index_test.zig`): link para arquivo, para título, wiki, link
  quebrado, "quem aponta pra cá" e nota nova no disco. `html.zig`, `sanitize.zig`, `anchor.zig` e
  `outline.zig` têm os seus.

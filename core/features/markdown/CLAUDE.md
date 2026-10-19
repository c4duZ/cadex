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
- Títulos e links extraídos com o tree-sitter de Markdown (o mesmo da feature editor, pela porta
  de entrada dela).
- Índice atualizado pela observação de arquivos da feature explorer.
- Âncora de título no mesmo formato do GitHub (minúsculas, espaços viram hífen).
- Spec de comportamento em docs/spec/markdown.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- Teste com uma pasta de exemplo: link para arquivo, para título, wiki, link quebrado e "quem aponta
  pra cá".

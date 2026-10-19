# editor (núcleo)

## O que eu quero
- Destaque de sintaxe e regiões de dobra para as linguagens comuns, com o tree-sitter.
- Atualizar só o trecho alterado quando o arquivo muda (reparse incremental).

## O que eu não quero
- Language server, autocomplete de código, vim ou formatar ao salvar
  (`../../../docs/adr/0006-editor-reads-code-edits-markdown.md`).
- Gramática de linguagem carregada sem o usuário abrir um arquivo dela.
- Travar em arquivo gigante: acima de um limite, mostra sem destaque.

## Como eu quero
- tree-sitter e as gramáticas em C, compilados pelo Zig (`core/build_grammars.zig`: uma biblioteca
  por gramática, porque cada parser.c traz o seu tree_sitter/parser.h; sempre ReleaseSmall). Versões
  em `core/build.zig.zon`, licenças no `NOTICE`. Gramática nova: pacote no zon, linha no
  build_grammars, linha em `languages.zig`, nota no `NOTICE`.
- Porta de entrada: `editor.zig`. `languages.zig` (nome do arquivo -> gramática e consulta; TS e TSX
  usam a consulta do JavaScript por baixo, C++ a do C), `query.zig` (consulta compilada uma vez por
  linguagem, com os predicados #eq? #match? #lua-match? #any-of?; classes do Perl e do Lua viram
  POSIX para o regex do sistema), `highlight.zig` (nome de captura -> tipo de trecho; @variable não
  pinta), `document.zig` (texto, árvore, edição incremental, faixas por intervalo: o nó mais interno
  vence, no mesmo nó o padrão mais tardio; Markdown com a gramática inline por cima dos parágrafos),
  `folds.zig` (dobras pelo tipo do nó, a mais externa por linha).
- Offsets na unidade da codificação: bytes em UTF-8, unidades de código em UTF-16 (o app manda o
  texto do NSString em UTF-16 e usa os offsets como NSRange). Acima de 1 MB, texto puro.
- API C em `c_api.zig` (`cadex_editor_*`).
- Spec: `docs/spec/editor.md`. Status: núcleo pronto (plano 5, fase A).

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- Teste: destaque e dobras de um arquivo de exemplo por linguagem batem com o esperado
  (`document_test.zig`); toda consulta compila contra a gramática (`query.zig`).

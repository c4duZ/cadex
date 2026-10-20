# markdown (app Windows)

## O que eu quero
- Escrever as notas do projeto como no Mac: autocomplete de caminho ao digitar `](`, de título
  depois de `#` e de nota ao digitar `[[`; Ctrl+clique num link abre o arquivo no título; link
  quebrado sublinhado em vermelho; "Quem aponta pra cá" na paleta.
- O botão "Visualizar" e markdown.toggle-preview levam ao renderizado, que é o documento da
  feature preview (o app o abre por Host.show_rendered).

## O que eu não quero
- Lógica de Markdown aqui: índice, links, títulos e âncoras vêm da feature markdown do núcleo.
- Sugestão ou conferência de links atrasando a digitação: os links são conferidos 400 ms depois de
  parar de digitar.
- Mexer no miolo do editor: a nota é um Editor com edição ligada e esta feature entra pelos Hooks.

## Como eu quero
- Porta de entrada: `markdown.zig`. `controller.zig`: Markdown (o índice das notas da raiz do
  workspace, `controller.zig:open` faz o Document de uma nota, seguir link, sugestões, backlinks) e
  Host, o que o app dá (editor.Host, abrir arquivo numa linha, abrir URL, mostrar renderizado,
  mostrar uma lista na paleta, busca de arquivos opcional).
- `index.zig`: cadex_markdown_* com as respostas em linhas separadas por tab. `session.zig`: uma
  por nota, pelos Hooks do editor (links e sublinhados, Ctrl+clique, sugestões, Enter que continua
  a lista, o botão). `trigger.zig`: o que completar, o caminho relativo e os offsets UTF-16 do
  núcleo em bytes; `lists.zig`: o próximo item de lista. Os dois puros e testados.
- `completion.zig`: a lista sob o cursor que não toma o teclado (↑ ↓ Enter Tab Esc vêm da sessão).
  `backlinks.zig`: a fonte da paleta de "Quem aponta pra cá".
- Comandos em `commands.zig`: markdown.toggle-preview (⇧⌘V), markdown.open-link,
  markdown.backlinks.
- Spec: `../../../../docs/spec/markdown.md`.

## Como validar
- `make windows-app` compila os testes (gatilhos, caminhos relativos, listas, respostas do núcleo);
  rodam na VM. Os arquivos puros também rodam aqui com `zig test` e um módulo win32 vazio.

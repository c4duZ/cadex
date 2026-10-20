# markdown-rendered (app Windows)

## O que eu quero
- O Markdown renderizado do Mac no Windows: o HTML do núcleo numa página, com as cores do tema,
  imagens locais e links que voltam para o app.
- Módulo próprio da feature markdown: o editor de notas (features/markdown) cria um Rendered e
  desenha no documento dele; os comandos de alternar são dele.

## O que eu não quero
- Script da nota executando: JavaScript desligado e a Content-Security-Policy do Mac.
- Imagem de fora do workspace; clique navegando a página para outro lugar.

## Como eu quero
- WebView2 pelo módulo `webview` (`../../../../docs/adr/0014-webview2-on-windows.md`), o HTML de
  `cadex_markdown_render` (`../../../../docs/adr/0010-markdown-rendering.md`).
- Porta de entrada: `markdown_rendered.zig` (`open` para uma aba só da página).
- `rendered.zig`: Rendered (a nota em https://note.cadex.example/<caminho>, servida pelo app:
  a página e as imagens, só dentro do workspace; `setText` com o texto do editor, `setLook` com o
  tema) e Host (`open_link`, atalho do app vindo da página).
- `links.zig`: o que um clique quer dizer (cadex-wiki: nome, arquivo com título, web), testado.
- `look.zig`: Look (as cores do terminal do tema, como o EditorLooks do Mac) e a página com o CSS
  do Mac, rgba com o alfa.
- Spec: `../../../../docs/spec/markdown.md`.

## Como validar
- `make windows-app` compila os testes (cadex-markdown-rendered-tests.exe); rodam na VM. Na VM: uma
  nota com imagem relativa, tabela, código colorido, `[[wiki]]` e `#título`.

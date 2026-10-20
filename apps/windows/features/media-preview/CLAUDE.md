# media-preview (app Windows)

## O que eu quero
- Imagem, vídeo, áudio e PDF do projeto numa aba, com o que o Windows já sabe mostrar.

## O que eu não quero
- Biblioteca de terceiros (FFmpeg, PDFium) para o que o sistema já faz.
- Ler arquivo fora do workspace; vídeo sem codec virando tela preta.

## Como eu quero
- Imagem parada pelo WIC num bitmap do Direct2D; GIF, SVG, vídeo, áudio e PDF pelo WebView2
  (`../../../../docs/adr/0014-webview2-on-windows.md`).
- Porta de entrada: `media_preview.zig` (`open`, `kindOf` para o app escolher o visualizador).
  `document.zig`: Media (só abre depois de `cadex_workspace_is_authorized`; sem conseguir, a
  mensagem e "Abrir no app padrão"; `diskMayHaveChanged` recarrega) e Host.
- `kind.zig`: o tipo pela extensão (o Windows não tem Quick Look: o resto é do editor).
- `image.zig`: ajusta à aba, zoom, arrasto e roda quando maior, Ctrl+roda dá zoom, xadrez,
  dimensões e tamanho; imagem acima de 8192 px reduzida pelo WIC antes de virar bitmap.
  `zoom.zig`: as contas do zoom e do arrasto, testadas.
- `page.zig`: a pasta do arquivo em https://media.cadex.example/, a página do player (controles do
  sistema, parado, erro avisado) e o PDF direto no visualizador do Edge (zoom, Ctrl+F e senha dele).
- `commands.zig`: media.zoom-in (Ctrl+=), media.zoom-out (Ctrl+-), media.zoom-fit (Ctrl+0),
  media.zoom-actual (Ctrl+Alt+0), os do Mac, disponíveis só com imagem; no PDF as teclas são do Edge.
- Spec: `../../../../docs/spec/media-preview.md`.

## Como validar
- `make windows-app` compila os testes (cadex-media-preview-tests.exe); rodam na VM. Na VM:
  `../../../../docs/cadex-icon.png` ajustado com zoom, um vídeo parado com controles, um PDF com busca.

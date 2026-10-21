# media-preview (app macOS)

## O que eu quero
- Ver imagem, vídeo, áudio e PDF numa aba, e outros formatos pelo Quick Look.

## O que eu não quero
- Biblioteca de terceiros para algo que o sistema já faz.

## Como eu quero
- ImageIO, AVKit, PDFKit e Quick Look.
- Porta de entrada: `MediaDocument.swift`, a aba (implementa o `TabDocument` das abas); só lê o
  arquivo depois de o núcleo dizer que está dentro do workspace; sem conseguir mostrar, oferece
  "Abrir no app padrão". `MediaKind.swift` escolhe o visualizador pelo tipo do sistema (texto e
  extensão desconhecida ficam com o editor). `ImageViewer.swift` (ajusta à aba, zoom, xadrez, tamanho
  e dimensões), `PDFViewer.swift` (páginas, zoom, ⌘F por uma barra própria, PDF com senha), vídeo e
  áudio no AVPlayerView parados, o resto no QLPreviewView.
- Comandos em `MediaCommands.swift`: media.zoom-in (⌘=), media.zoom-out (⌘-), media.zoom-fit (⌘0),
  media.zoom-actual (⌥⌘0; ⌘1 é das abas).
- Spec: `docs/spec/media-preview.md`. Status: plano 5, fase D pronta.
- Fontes e medidas principais da interface vêm de UILooks (`../../shared/looks/CLAUDE.md`): zoom, densidade e fonte da interface, lidos ao montar a tela.

## Como validar
- `make macos-test` passa: tipo de arquivo -> visualizador; imagem abre dentro e não abre fora do
  workspace.

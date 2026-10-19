# 0001 — macOS primeiro, app nativo por plataforma

Data: 2026-10-19 · Status: aceita

## Contexto
O ponto de partida é o Terax, um app Tauri (Rust + WebView + React). Ele roda em macOS, Linux e
Windows, mas carrega um runtime web inteiro e o JavaScript da interface. O objetivo do Cadex é ser o
mais leve e rápido possível em cada sistema.

## Decisão
- Cada plataforma tem uma interface nativa própria, fina, por cima de um núcleo compartilhado
  (ver ADR 0002).
- macOS vem primeiro: Swift com AppKit, renderização do terminal em Metal, e os frameworks do
  sistema para mídia (ImageIO, PDFKit, AVKit, Quick Look).
- Windows vem depois, sobre o mesmo núcleo. A pasta `apps/windows/` fica reservada. (A stack foi
  decidida no ADR 0012: Zig com Win32 e Direct3D 11.)
- Linux está fora do escopo por enquanto.

## Consequências
- Previews de mídia não custam peso: os frameworks já vêm no sistema.
- Cada feature de interface é escrita uma vez por plataforma. Por isso a lógica fica no núcleo e a
  interface só desenha e repassa entrada.
- Não propor voltar para WebView/Electron/Tauri "para ter as três plataformas de uma vez": foi o
  ponto de partida e foi descartado por peso.
- O editor de código é o maior risco técnico: não há equivalente nativo pronto ao CodeMirror.
  A escolha do componente de editor ainda não foi feita e merece um ADR próprio.

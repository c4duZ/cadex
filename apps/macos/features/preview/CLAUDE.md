# preview (app macOS)

## O que eu quero
- Preview web de servidores locais detectados e de URLs externas.

## O que eu não quero
- Preview com acesso aos arquivos ou à API do app.

## Como eu quero
- WKWebView isolada do resto do app: `PreviewDocument.swift` é a aba (implementa o `TabDocument`),
  com dados do site só enquanto o app está aberto, nenhum script do app na página, file: e esquemas
  estranhos recusados (mailto: e afins vão para o sistema), janela nova vai para o navegador,
  "Inspecionar elemento" no menu da página. Barra com voltar, avançar, recarregar e endereço; título
  da página na aba; progresso fino; erro de conexão com o motivo. A página carrega quando a aba
  aparece pela primeira vez (carregada antes de estar numa janela, não desenhava).
- Identidade da aba pelo endereço: a oferta do terminal para um endereço já aberto recarrega aquela
  aba; preview em branco é sempre aba nova.
- Comandos em `PreviewCommands.swift`: preview.open (onde a configuração diz), preview.open-in-tab, preview.reload (⌘R), preview.back,
  preview.forward. A oferta "Abrir no preview" é da feature terminal (`../terminal/TerminalPreviewOffer.swift`)
  e chega aqui pelo app (`onOpenPreview` das abas).
- Spec: `docs/spec/preview.md`. Status: plano 5, fase E pronta.

## Como validar
- `make macos-test` passa: sem esquema, http para servidor local e https para o resto, e só esquemas web, mesma aba para o mesmo
  servidor, página sem ponte com o app.
- No app: `Cadex <pasta> http://localhost:8000/` abre o endereço numa aba de preview.

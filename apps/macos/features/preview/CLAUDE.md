# preview (app macOS)

## O que eu quero
- Preview web de servidores locais detectados e de URLs externas.

## O que eu não quero
- Preview com acesso aos arquivos ou à API do app.
- Canal da página para o app (`WKScriptMessageHandler`), script fixo no mundo da página
  (`WKUserScript`) ou colar o elemento escolhido com Enter (`../../../../docs/adr/0018-element-picker.md`).

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
- Escolher elemento (plano 16): `PreviewPicker.swift` liga e desliga o modo, pergunta ao script do
  mundo isolado `cadex-picker` (`PickerScript.swift`, injetado sob demanda e de novo a cada
  navegação, sem `WKUserScript`), uma pergunta por vez no hover, e entrega o clique por
  PreviewDocument.onPickElement, que o app liga (`../../app/ElementPickDelivery.swift`); sem ele,
  copia. `PickingWebView.swift` engole movimento, clique e arrasto com o modo ligado (a página não
  recebe hover nem clique; a rolagem passa) e o modo acaba quando a web view perde o foco.
  `PickerOverlay.swift` desenha contorno, etiqueta, faixa e o aviso verde/âmbar por cima, fora do
  DOM. `PickedElement.swift` é o texto entregue (limites, sem caracteres de controle, entre
  `<picked_element>`), puro e testado. Comandos preview.pick-element (⌘⇧C, também o botão de mira
  da barra, que roda o comando pelo `runCommand`) e preview.stop-picking (Esc, só escolhendo e com o
  preview focado); só no Mac.
- Spec: `docs/spec/preview.md`. Status: plano 5, fase E pronta; plano 16, fase A no código.
- Fontes e medidas principais da interface vêm de UILooks (`../../shared/looks/CLAUDE.md`): zoom, densidade e fonte da interface, lidos ao montar a tela.

## Como validar
- `make macos-test` passa: sem esquema, http para servidor local e https para o resto, e só esquemas web, mesma aba para o mesmo
  servidor, página sem ponte com o app (nenhum `WKUserScript`, com o modo ligado ou não), o texto
  entregue (limites e limpeza) e, numa página de teste, o mundo do seletor devolvendo seletor,
  texto, HTML e caixa sem a página enxergá-lo.
- No app: `Cadex <pasta> http://localhost:8000/` abre o endereço numa aba de preview.

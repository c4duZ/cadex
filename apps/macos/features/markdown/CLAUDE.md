# markdown (app macOS)

## O que eu quero
- Markdown renderizado com GitHub Flavored Markdown, alternando com o texto.
- Editando Markdown: autocomplete de caminho ao digitar `](`, de título depois de `#` e de nota ao
  digitar `[[`.
- ⌘+clique num link abre o arquivo no título certo; link quebrado sublinhado.
- Painel "quem aponta pra cá" com os arquivos que linkam o arquivo atual.

## O que eu não quero
- HTML do arquivo executando script.
- Sugestão atrasando a digitação.

## Como eu quero
- Respostas vêm da feature markdown do núcleo; esta feature só mostra (lista de sugestões,
  sublinhado, painel) e se liga ao editor pela porta de entrada dele.
- Abrir link, alternar texto e renderizado e mostrar "quem aponta pra cá" são comandos registrados.
- Conteúdo sanitizado antes de exibir.
- Porta de entrada: `MarkdownController.swift` (o índice das notas, `attach` de cada nota aberta no
  editor, alternar o renderizado, seguir links, sugestões, "quem aponta pra cá" como lista da
  paleta). `MarkdownIndex.swift` fala com a feature markdown do núcleo.
- `MarkdownSession.swift`, uma por nota aberta: confere os links um pouco depois de parar de
  digitar, sublinha os quebrados com atributos do texto (os de desenho do TextKit 2 se perdiam quando
  o editor repintava as cores), ⌘+clique pelo gancho do editor, sugestões por
  `CompletionTrigger.swift` (o que completar e o caminho relativo) e `CompletionPopup.swift` (lista
  que não toma o teclado; ↑ ↓ Enter Tab Esc vêm do delegate do texto).
- `MarkdownPreview.swift`: WKWebView sem JavaScript, CSP que só deixa imagens cadex-file: e estilo
  embutido, imagens servidas só de dentro do workspace; clique em link volta para o app (nota abre no
  Cadex no título, web no navegador). Cores do `EditorAppearance` (rgba, com o alfa). A página
  é da nota enquanto aparece: voltar para o texto ou fechar a aba libera o WebKit, e alternar de
  novo renderiza outra (o controlador não guarda nenhuma).
- `MarkdownToggle.swift`: o botão "Visualizar"/"Código" no canto da aba (o acessório do editor),
  que roda markdown.toggle-preview; `opensRendered` (markdown.openAs do settings.json, que o app
  passa) abre a nota já renderizada.
- Comandos em `MarkdownCommands.swift`: markdown.toggle-preview (⇧⌘V), markdown.open-link,
  markdown.backlinks.
- Spec: `docs/spec/markdown.md`. Status: plano 5, fase C pronta.

## Como validar
- `make macos-test` passa: o que completar, caminhos relativos, página sem script, links quebrados,
  sugestões de nota e título, backlinks, seguir link.

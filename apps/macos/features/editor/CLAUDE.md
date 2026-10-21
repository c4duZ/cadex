# editor (app macOS)

## O que eu quero
- Ler código: números de linha, setinha de dobrar, destaque de sintaxe e linha atual destacada.
- Edições pequenas, com o que o NSTextView já dá (digitar, desfazer, buscar).
- Abrir arquivo grande sem travar; avisar quando é binário.

## O que eu não quero
- Biblioteca de editor de terceiros, language server, autocomplete de código, vim ou formatar ao
  salvar (`../../../../docs/adr/0006-editor-reads-code-edits-markdown.md`).
- Recolorir o arquivo inteiro a cada tecla.

## Como eu quero
- Porta de entrada: `EditorDocument.swift`, a aba de um arquivo (implementa o `TabDocument` das
  abas): lê pelo núcleo (`EditorFile.swift`: até 10 MB, acima disso o começo só para leitura;
  binário vira mensagem com "Abrir no app padrão"), salva pelo núcleo (gravação atômica, dentro do
  workspace), segue o disco (`EditorDocument+Disk.swift`: recarrega sem edição pendente, pergunta
  com edição), vai para uma linha, pergunta ao fechar com mudança.
- Texto: `CodeTextView.swift` (NSTextView com TextKit 2; até EditorFile.wholeLayoutBytes (256 KB)
  faz o layout do texto inteiro ao abrir, a cada largura nova e a cada edição, porque o TextKit 2
  estima o que está fora da tela e o texto pulava (issue #2); as dobras só refazem o layout quando
  as linhas escondidas mudam; linha atual, Tab com a indentação do
  arquivo, ⌘F pelo comando edit.find), `LineRuler.swift` (números e setinhas de dobra; lê só o
  TextKit 2, porque tocar no layoutManager antigo volta o NSTextView ao TextKit 1),
  `EditorFolding.swift` (dobra escondendo parágrafos pelo delegate do NSTextContentStorage, sem
  mexer no texto; uma edição desdobra tudo), `LineIndex.swift` (inícios de linha em UTF-16).
- Cores: `EditorSyntax.swift` fala com a feature editor do núcleo em UTF-16 (offsets viram NSRange
  direto); `EditorHighlighter.swift` pinta no NSTextStorage só as linhas que o núcleo diz que
  mudaram, depois de a edição terminar. `EditorAppearance.swift`: fonte e cores, que o app preenche
  (a fonte do terminal e a paleta ANSI do tema). `EditorColoring.swift`: pinta um texto inteiro com
  as mesmas cores, para quem mostra código sem editar (o diff do git).
- Ganchos para outras features (markdown): `textView`, `commandClick` (⌘+clique num caractere) e
  `showAlternate(_:)` (outra view no lugar do texto, como o renderizado).
- Comandos em `EditorCommands.swift`: editor.save (⌘S), editor.fold-all, editor.unfold-all.
- A inteligência de Markdown (autocomplete, ⌘+clique, links quebrados, quem aponta pra cá) vem da
  feature markdown, pela porta de entrada dela.
- Spec: `docs/spec/editor.md`. Status: plano 5, fase B pronta (código). Markdown na fase C.
- A faixa de aviso usa a fonte da interface (UILooks, `../../shared/looks/CLAUDE.md`); o código e os números de linha seguem a fonte do terminal, sem o zoom da interface.

## Como validar
- `make macos-test` passa: índice de linhas, indentação, abrir Zig com cores e dobras, salvar,
  recarregar do disco, binário.
- No app sem tomar o teclado: `Cadex <arquivo>` abre o arquivo numa aba; os comandos estão nos menus.

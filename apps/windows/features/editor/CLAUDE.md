# editor (app Windows)

## O que eu quero
- Ler código como no Mac: números de linha, setinha de dobrar, destaque de sintaxe do núcleo e
  linha atual destacada, com a fonte e as cores do terminal do tema.
- Abrir arquivo grande sem travar (os primeiros 10 MB, só leitura, com aviso); binário vira
  mensagem com "Abrir no app padrão".
- A mesma vista, com edição ligada, é o editor de notas da feature markdown.

## O que eu não quero
- Editar código (`../../../../docs/adr/0006-editor-reads-code-edits-markdown.md`): a vista de
  código é só leitura; seleção, cópia e busca funcionam.
- Biblioteca de editor, language server, autocomplete de código, vim ou formatar ao salvar.
- Desenhar ou medir o arquivo inteiro a cada quadro: só as linhas na tela vão ao DirectWrite.

## Como eu quero
- Porta de entrada: `editor.zig` (`editor.zig:open` faz o Document de um arquivo; `reload`,
  `goToLine`, `pathOf` para o app). `document.zig`: Editor, o Document das abas: lê pelo núcleo
  (`file.zig`, os limites e mensagens do Mac), salva quando a edição está ligada, segue o disco
  (`document.zig:reload`: sem mudança pendente recarrega mantendo o cursor; com mudança pergunta
  no `banner.zig` com "Recarregar" e "Manter o meu") e Host (abrir no app padrão, documento com
  foco).
- Texto puro e testado: `buffer.zig` (bytes UTF-8, inícios de linha, cursor, seleção, movimentos
  por caractere, palavra, Home esperto, CRLF mantido), `history.zig` (desfazer uma palavra por vez),
  `wrap.zig` (colunas monoespaçadas, tab até a parada de 4, largos valem 2, quebra depois de
  espaço), `folding.zig` (regiões do núcleo, dobradas), `rows.zig` (as linhas na tela: quebradas
  na largura, sem as dobradas).
- `view.zig`: View, a vista (medidas da fonte, roda de 3 linhas, revelar o cursor, Hooks para a
  markdown: teclas antes, mudança, Ctrl+clique, sublinhados, desenho por cima, fechar).
  `view_draw.zig`: fundo, linha atual, buscas, seleção, texto por linha com as cores do núcleo
  (`../../shared/gfx/painter.zig:textColored`), sublinhado pontilhado, cursor com o texto do IME,
  calha. `view_input.zig`: mouse (clique, Shift, duplo, triplo, arrastar com autoscroll, setinha) e
  teclas do Windows (Ctrl+C, Ctrl+A, Ctrl+F sempre; editando: digitar, apagar, Enter com a
  indentação, Tab, Ctrl+Z, Ctrl+Y, Ctrl+X, Ctrl+V).
- `syntax.zig`: cadex_editor_* em UTF-8 (offsets iguais aos do buffer). `appearance.zig`: fonte e
  cores, que o app preenche (`appearance.zig:fromTerminal`, as cores do Mac pela paleta ANSI).
  `find.zig`: a barra de busca do edit.find (âmbar e laranja, "3 de 12", Enter, Shift+Enter, Esc).
- Comandos em `commands.zig`: editor.save (⌘S, só com edição ligada), editor.fold-all,
  editor.unfold-all.
- Spec: `../../../../docs/spec/editor.md`.
- O código fica no `window_scale` do Style: o zoom da interface (plano 15) não muda a fonte do
  editor, que é a do terminal.

## Como validar
- `make windows-app` compila os testes (buffer, histórico, quebra, dobras, linhas na tela, bytes
  ruins); rodam na VM. Os arquivos puros também rodam aqui com `zig test` e um módulo win32 vazio.

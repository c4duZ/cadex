# Plano 8 — Documentos em painéis, ao lado do terminal (v1.0)

Depende de: planos 1 a 7 (v0.1.1 publicada) · Features: tabs, spaces, settings, explorer, editor,
markdown, media-preview, preview, source-control, git-history (app) · Specs a mudar: tabs,
settings, explorer, spaces.

## O que eu quero
- Abrir arquivo de código, Markdown, imagem, vídeo, áudio, PDF, preview web, diff e histórico do git
  **num painel ao lado de um terminal**, na mesma aba. O dono sente muita falta disso (2026-10-19).
- O painel de documento funciona **idêntico a um painel de terminal hoje**: dividir (⌘D, ⌘⇧D),
  passar o foco (⌘], ⌘[, ⌘⌥ + seta, clique), fechar (⌘W, ×), arrastar o divisor, tamanhos
  iguais (PaneTree.balanced()), escurecer quando sem foco, salvar e restaurar o layout nos spaces.
- Uma configuração da abertura padrão de arquivos, em Configurações → Geral, "Abrir arquivos":
  **Ao lado** (padrão) ou **Em nova aba**. Tem de funcionar de cara, sem o usuário configurar nada.
- Escolher na hora, sem mudar a configuração: "Abrir ao lado" e "Abrir em nova aba" no menu de
  contexto do explorer e na paleta.

## O que eu não quero
- Uma pilha de divisões a cada arquivo aberto: abrir ao lado reusa o painel de documento da aba.
- Perder mudança não salva ao trocar o documento de um painel.
- Quebrar os spaces.json que já existem (formato do plano 7): eles têm de abrir igual.
- Feature importando o miolo de outra: as abas continuam vendo só o protocolo `TabDocument`.

## Como eu quero
**Onde estamos (2026-10-19, v0.1.1).** Uma aba (`apps/macos/features/tabs/Tab.swift`) guarda só
terminais: `panes: [Int: TerminalView]`, `focusedPane`, a árvore em `PaneLayoutView`. Os documentos
vivem fora das abas de terminal: TabsController.documents: [Int: TabDocument], uma aba inteira por
documento (`open(_:)`, `activeDocument`, `document(identity:)`, `allDocuments`). Arquivos do mapa:
- `apps/macos/features/tabs/`: `apps/macos/features/tabs/Tab.swift` (painéis, foco, split, remove, snapshot),
  `apps/macos/features/tabs/TabsController.swift` (documents, open, activeTerminal/activeDocument, refreshBar, makeTerminal,
  split, wire, tabIcon/tabImage), `apps/macos/features/tabs/TabsClosing.swift` (closeFocusedPane, removePane, closeTab,
  remove, shouldClose), `apps/macos/features/tabs/TabsRestore.swift` (snapshot, restore, restoreTerminal, setShown,
  closeAll), `apps/macos/features/tabs/TabsSnapshot.swift` (Item .terminal(title, layout, focus) e .document(identity);
  Layout .pane(folder:) e .split), `apps/macos/features/tabs/PaneTree.swift` (`balanced()`), `apps/macos/features/tabs/PaneLayoutView.swift` (já
  aceita qualquer NSView como painel; escurece os sem foco), `apps/macos/features/tabs/TabBarView.swift`, `apps/macos/features/tabs/TabDocument.swift`.
- App: `apps/macos/app/FileOpener.swift` (open, openDiff, openHistory, foldersChanged),
  `apps/macos/app/SpacesWiring.swift` (makeTabs, startSpaces, reopen), `apps/macos/app/main.swift`
  (openPreview, registro de comandos, onEditorOpened → markdown.attach), `apps/macos/app/FolderFollow.swift`.
- Explorer: ExplorerController.openFile (closure `(String) -> Void`), `apps/macos/features/explorer/ExplorerCommands.swift`
  (tabela e menu de contexto), `apps/macos/features/explorer/ExplorerActions.swift` (openSelection).
- Settings: `apps/macos/features/settings/Settings.swift`, `apps/macos/features/settings/SettingsFile.swift`, `apps/macos/features/settings/GeneralPages.swift`,
  `apps/macos/app/SettingsBridge.swift` (padrão: cada seção chega ao app por um `onX`).

**Decisões (tomadas com o dono, 2026-10-19):**
- Todo painel guarda um terminal **ou** um documento. Em `Tab`, `panes: [Int: Pane]` com
  `enum Pane { case terminal(TerminalView), document(TabDocument) }` e `view`. Uma aba de documento
  passa a ser uma aba com um painel só; o dicionário `documents` do TabsController some.
- "Ao lado", nesta ordem: (1) arquivo já aberto em algum painel de qualquer aba → vai para ele (aba
  e foco); (2) a aba ativa já tem um painel de documento sem mudança não salva → o novo documento
  troca o conteúdo dele (fecha o antigo com `close()`); (3) senão, divide o painel com foco para a
  direita (.horizontal, depois `balanced()`) e o documento entra no painel novo, com o foco;
  (4) sem espaço para dividir (`canSplit` falso) → nova aba. "Em nova aba": o comportamento de hoje.
- Configuração general.openFiles = `"beside"` (padrão) ou `"tab"` no settings.json; linha "Abrir
  arquivos" em Geral (popup Ao lado / Em nova aba).
- Comandos novos (ADR 0005): explorer.open-beside ("Abrir ao lado") e explorer.open-in-tab
  ("Abrir em nova aba"), no menu de contexto do explorer logo depois de "Abrir arquivo";
  explorer.open segue a configuração. O explorer não conhece abas: ganha uma closure
  `openFileAs: ((String, Bool) -> Void)?` (caminho, ao lado?) que o app liga ao FileOpener.
- Quem abre segue a configuração: arquivos (FileOpener.open), mídia, diff (`openDiff`), histórico
  (`openHistory`), preview web (`openPreview` em main.swift) e a oferta "Abrir no preview" do
  terminal (servidor e página lado a lado).
- ⌘D/⌘⇧D com o foco num documento: terminal novo ao lado, na pasta do arquivo.
- Foco por clique num documento: `NSClickGestureRecognizer` no painel (contêiner do documento),
  `delaysPrimaryMouseButtonEvents = false`, chamando tab.noteFocus(pane) como o `onFocus` do
  terminal já faz. `focus(pane)` de documento chama document.focus().
- Título e ícone da aba vêm do painel com foco (terminal: pasta ou programa; documento: título e
  `tabIcon`/`tabImage`). "●" no título se qualquer painel da aba tem mudança não salva.
- Fechar: painel de documento pergunta pelo `confirmClose` dele; fechar aba ou janela soma os não
  salvos de todos os painéis (CloseConfirmation.confirmUnsaved) e os programas rodando.
- `activeTerminal` e `activeDocument` passam a ser os do painel com foco da aba ativa;
  `document(identity:)` e `allDocuments` procuram em todos os painéis de todas as abas. Status bar,
  FolderFollow e os comandos que usam `activeDocument` (editor, markdown, mídia, preview, diff,
  histórico) continuam funcionando sem mudar.
- Snapshot: TabsSnapshot.Layout ganha .document(identity: String) ao lado de
  .pane(folder:). O item antigo .document(identity) continua sendo lido e vira uma aba de um
  painel; na escrita, toda aba sai como .terminal(title, layout, focus) (nome mantido pelo JSON).
  O restore recebe do app uma closure que **faz** o documento pela identidade, sem abri-lo
  (`(String) -> TabDocument?`, um FileOpener.makeDocument); se não der (arquivo sumiu), o painel
  vira um terminal na pasta do arquivo, para o layout não mudar.
- A ajuda do Markdown (markdown.attach) e o botão Visualizar/Código continuam valendo para notas em
  painel, porque saem de `onEditorOpened` no FileOpener.

**Fases:**
- **A. Spec e modelo:** `docs/spec/tabs.md` (seção "Documentos em painéis" com as regras acima),
  `docs/spec/settings.md` (general.openFiles), `docs/spec/explorer.md` (os dois comandos),
  `docs/spec/spaces.md` (documentos dentro do layout). Depois `Pane` em `apps/macos/features/tabs/Tab.swift` e o
  TabsController sem `documents`, com testes usando um `TabDocument` falso: abrir em nova aba,
  activeDocument/activeTerminal pelo foco, document(identity:) em painéis.
- **B. Abrir ao lado:** `open(_:beside:)` com as quatro regras, a configuração ligada pelo
  SettingsBridge, os comandos do explorer, FileOpener/openPreview/oferta do terminal seguindo a
  configuração. Testes de cada regra (inclusive não salvo e sem espaço).
- **C. Foco, título e fechar:** clique dá foco ao documento, ⌘]/⌘[/setas passam por documentos,
  ⌘D num documento abre terminal, título/ícone/● pelo painel, fechar painel/aba/janela perguntando.
- **D. Salvar e restaurar:** Layout .document, restore com `makeDocument`, compatibilidade com o
  spaces.json do plano 7 (teste com um JSON antigo), documento sumido vira terminal.
- **E. Conferir e empacotar:** no app, abrir um arquivo ao lado de um terminal, trocar o documento,
  dividir de novo, fechar, sair e reabrir; `make package`; atualizar CLAUDE.md das features e o
  README (seção O que é).

## Como validar
- `make check` passa ao fim de cada fase.
- Testes do TabsController com documento falso: as quatro regras de "ao lado", nova aba, foco por
  painel, fechar com não salvo, snapshot ida e volta com documentos, JSON antigo do plano 7 lido
  igual.
- No app sem roubar o teclado nem o mouse do dono (memória do projeto): `CADEX_BACKGROUND=1`,
  `CADEX_SPACES_FILE` de teste, comandos pelos itens de menu do processo (System Events mirando
  `first application process whose unix id is <pid>`, nunca pelo nome: o Cadex do dono também se
  chama Cadex), captura pelo pid (helper que filtra `kCGWindowOwnerPID`). Um spaces.json de teste
  com um terminal e um documento lado a lado serve para ver o layout sem digitar nada.
- Atualizar specs, CLAUDE.md das features tocadas e o status em `docs/plans/README.md`.

## Fechamento (2026-10-19)
Fases A a E feitas. Conferido no app em segundo plano: terminal e documento lado a lado voltam do
spaces.json; abrir um arquivo pela linha de comando troca o documento do painel (regra 2); ⌘D num
documento abre terminal na pasta dele, três painéis iguais; fechar devolve o espaço; sair e reabrir
guarda o layout. `make package` passa.

Desvio do plano: quem pede a abertura (o histórico abrindo um diff, o diff abrindo o arquivo) fica
no painel dele (`keeping` em `open(_:beside:keeping:)`); sem isso, a regra 2 trocava o histórico
pelo diff. O clique em documento usa um reconhecedor que falha na hora (`PanePressRecognizer`) em
vez do `NSClickGestureRecognizer`, para que arrastar seleção também dê o foco.

Falta o dono conferir à mão: clicar num documento e ver o escurecimento passar para o terminal;
"Abrir ao lado" e "Abrir em nova aba" no menu de contexto do explorer; a configuração "Abrir
arquivos" em Geral; abrir um diff pelo histórico e um preview pela oferta do terminal; editar um
arquivo ao lado (sem salvar) e abrir outro (deve dividir, não trocar); ⌘W com arquivo não salvo.

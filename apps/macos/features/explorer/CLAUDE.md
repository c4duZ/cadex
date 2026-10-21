# explorer (app macOS)

## O que eu quero
- Árvore de arquivos com ícones, busca, navegação por teclado, renomear inline e ações de contexto.
- Atualização ao vivo quando o disco muda; marcar arquivos alterados no git.

## O que eu não quero
- Ler o disco direto do Swift: tudo passa pela feature explorer do núcleo.

## Como eu quero
- Árvore carregada sob demanda, pasta por pasta.
- A raiz da árvore é o workspace: `WorkspaceFolder.swift` guarda a pasta aberta (a da linha de
  comando, senão a pasta pessoal), autoriza no núcleo cada pasta que vira raiz e avisa a troca por
  `onChange`. `launchedWithFolder` diz se o app abriu numa pasta (sem ela, os spaces devolvem a
  última); `allow` autoriza a pasta de um documento restaurado sem virar raiz. A feature workspace não tem pasta no app; a parte dela que o usuário vê mora aqui.
- Comandos em `WorkspaceCommands.swift`: `workspace.open-folder` ("Abrir pasta…", ⌘O, seletor do
  sistema) e `workspace.use-terminal-folder` (a pasta do terminal com foco, que `apps/macos/app/main.swift`
  passa por closure: o explorer não vê terminais).
- A árvore: `ExplorerController.swift` (porta de entrada: a view do painel lateral, com o nome da
  pasta pequeno e cinza e as ações à direita, buscar arquivo, novo arquivo, nova pasta, recarregar; a raiz, o
  watcher, recarregar mantendo pastas abertas e seleção, mensagem curta embaixo da árvore),
  `ExplorerRowView` (no `ExplorerDataSource.swift`: a seleção na cor do tema, visível com ou sem
  foco), `FileNode.swift` (uma linha; pasta lida só ao abrir; recarga reaproveita linhas iguais; notas
  "Pasta vazia" e "Sem permissão"), `ExplorerDataSource.swift` (dados, células desenhadas à mão no
  `layout()`, arrastar e soltar), `ExplorerOutline.swift` (teclas da árvore; o clique direito abre o menu de
  `ExplorerContextMenu.swift`, que monta pelo tipo (pasta: terminal e Finder; arquivo: as formas de
  abrir) e deixa de fora o que não roda, nada apagado, no
  menu do app de `apps/macos/shared/menus`),
  `ExplorerRename.swift` (renomear no lugar), `ExplorerActions.swift` (o que cada comando faz e
  quando está indisponível), `FileTypeIcon.swift` (pasta, link, e os arquivos pelo `FileIcons` compartilhado).
- Um clique abre (arquivo na aba, pasta abre ou fecha); ⌘ e ⇧ só selecionam; a seta não abre duas
  vezes. Dois cliques numa pasta rodam explorer.open-in-terminal (o app faz `cd` ou, com programa
  rodando, abre aba nova na pasta). Aparência do VS Code (spec, "Aparência"): linhas de 22 pt, recuo de 8 pt, guias de recuo com o
  ponteiro sobre a árvore e fundo leve na linha sob ele (`ExplorerOutline.swift` e
  `ExplorerRowView`), cores por tipo em `apps/macos/shared/icons/FileIcons.swift` (da tabela do CodeEdit,
  MIT, no NOTICE). `ExplorerCompact.swift`: pastas compactas; a linha é a primeira pasta da cadeia,
  mostra os filhos da última e as ações valem para a última (`tail`, `item(of:)`, `row(of:)`,
  `parentFolder(of:)`: a última pasta não é item do outline, então nada pergunta ao outline quem é
  o pai). `ExplorerExpanded.swift`: as pastas abertas por raiz, nas preferências do app (estado, não
  configuração). Renomeando, nome que seria recusado deixa o campo vermelho.
- Disco só pelo núcleo: `ExplorerFiles.swift` (API C do explorer; a Lixeira é a do sistema, com a
  pasta do item checada no workspace) e `FileWatcher.swift` (FSEvents do núcleo; o callback é uma
  função solta, fora da main actor, que passa o lote para a thread principal).
- Comandos em `ExplorerCommands.swift` (categoria Arquivo). Atalhos globais só ⇧⌘E (focar a árvore)
  e ⇧⌘. (ocultos). Enter, F2, ⌘⌫, ⌘C e ⌘V são teclas da árvore (`ExplorerOutline.swift`) que
  disparam os mesmos comandos pelo id, porque o terminal precisa dessas teclas.
- Arrastar linhas: para o terminal vira caminho escapado (o terminal já aceita arquivos), para o
  Finder copia, para uma pasta da árvore move. Arquivos de fora soltos na árvore ainda não entram.
- "Mostrar ocultos" é explorer.showHidden no settings.json (padrão: mostrar, apagados); o app liga.
- Abrir um arquivo chama `openFile` (o app abre ao lado ou em nova aba, pela configuração); sem ele,
  o app padrão do sistema. explorer.open-beside e explorer.open-in-tab ("Abrir ao lado", "Abrir em
  nova aba", no menu de contexto logo depois de "Abrir arquivo") chamam `openFileAs` com a escolha;
  o explorer não conhece abas.
  `onFolderChange` repassa as pastas que mudaram no disco (o app avisa os editores abertos). Marca de ignorado pelo
  .gitignore entra na fase D. `gitMarks` (caminho -> letra, vindo do source control pelo app) pinta
  o nome com a cor do tipo de mudança e põe um ponto nas pastas que contêm alterados.
- Spec: `docs/spec/explorer.md` e `docs/spec/workspace.md`. Status: plano 4, fases A e C prontas.
- Fontes e medidas principais da interface vêm de UILooks (`../../shared/looks/CLAUDE.md`): zoom, densidade e fonte da interface, lidos ao montar a tela.

## Como validar
- `make macos-test` passa: árvore (recarga mantém linhas, ocultos, notas), operações recusadas,
  ícones e cores, pastas compactas (e a cadeia que se desfaz), pastas abertas que voltam, watcher
  entregando na thread principal.
- No app, sem roubar o teclado: a árvore é acessível (linhas, AXSelected, triângulo com AXPress) e
  os comandos estão no menu Arquivo.

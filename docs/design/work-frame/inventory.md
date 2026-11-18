# Inventário da casca velha

O que a moldura nova (`docs/adr/0035-work-frame.md`, planos 25 a 30) substitui, peça por peça, e o
plano que tira cada uma. Levantado em 2026-11-17 a partir dos manifestos e do código.

## O que eu quero
- Nenhuma casca velha sobrando: toda peça de hoje tem destino e plano. Quando o plano tira a peça,
  o estado dela vira `saiu`, e `tools/check_leftovers.py` (plano 25, fase B; roda no `make
  manifests`) falha se ela ainda existe:
  - `arquivo`: o caminho não pode existir;
  - `comando`: o id entre aspas não pode aparecer em `apps/macos/`, `core/` nem `tools/`;
  - `chave`: a chave não pode aparecer em `apps/macos/` (só na migração, marcada `// migração 0035`);
  - `gancho`: a variável não pode aparecer em `apps/macos/` nem em `tools/perf/`;
  - `spec` e `trecho`: o texto entre aspas citado não pode aparecer no arquivo dito (a fase que
    tira a peça escreve na linha o texto exato a procurar).
- Estados: `fica` (sem mudança), `muda` (a mesma peça, com cara ou lugar novo), `sai` (o plano a
  tira), `saiu` (já tirada; conferida pela máquina).

## O que eu não quero
- Peça nova da moldura sem linha aqui quando ela substitui uma velha.
- Apelido de comando vivendo mais de um plano: o comando velho que vira apelido do novo sai no
  plano seguinte.
- Chave de configuração velha lida para sempre: é migrada uma vez, na abertura, e a leitura sai no
  plano seguinte.

## Como eu quero

### Barra de título e janela (plano 26)
| tipo | peça | estado | destino | plano |
|---|---|---|---|---|
| arquivo | `apps/macos/app/TitleBarView.swift` | muda | a barra nova: busca, projeto › tarefa, abas, quadro, sino, painel da direita | 26 |
| arquivo | `apps/macos/app/TitleBarButton.swift` | muda | o botão de ícone da barra nova (components.titleIconButton), feito | 26 |
| arquivo | `apps/macos/app/WorkspaceView.swift` | muda | as quatro regiões | 26 |
| arquivo | `apps/macos/app/PanelView.swift` | muda | o painel arredondado das fundações | 26 |
| trecho | "spaceButton" em `apps/macos/app/TitleBarView.swift` | saiu | o botão de space saiu da barra; space.switch no ⌘K até virar project.switch (plano 27) | 26 |
| trecho | "spaceActions" em `apps/macos/app/PaletteWiring.swift` | saiu | o menu do clique direito no botão de space | 26 |
| trecho | "sidebarButton" em `apps/macos/app/TitleBarView.swift` | saiu | ⌘B e view.toggle-sidebar no ⌘K | 26 |
| trecho | "powerButton" em `apps/macos/app/TitleBarView.swift` | saiu | o café é o item keepAwake da barra de status (power.toggle) | 26 |
| trecho | "updateButton" em `apps/macos/app/TitleBarView.swift` | saiu | o item update da barra de status, só com versão nova (app.check-for-updates) | 26 |
| trecho | "settingsButton" em `apps/macos/app/TitleBarView.swift` | saiu | só ⌘, e o menu | 26 |
| arquivo | `apps/macos/features/tabs/TabBarView.swift` | muda | as abas com estado e a largura do título (components.tab), feito | 26 |
| arquivo | `apps/macos/features/tabs/TabAgentTitle.swift` | muda | vira a peça de estado das fundações | 25 |

### Barra lateral de ícones (planos 26 e 27)
| tipo | peça | estado | destino | plano |
|---|---|---|---|---|
| arquivo | `apps/macos/features/sidebar/SidebarIconRow.swift` | saiu | a árvore do trabalho (fase D) | 27 |
| arquivo | `apps/macos/features/sidebar/SidebarIconButton.swift` | saiu | a árvore do trabalho (fase D) | 27 |
| arquivo | `apps/macos/features/sidebar/SidebarSubtabs.swift` | saiu | as sub-abas eram do sino (virou popover), com SidebarItem.subtabs e select(subtab:of:) | 26 |
| arquivo | `apps/macos/features/sidebar/SidebarLayout.swift` | saiu | a árvore não tem ordem de ícones (fase D) | 27 |
| arquivo | `apps/macos/features/sidebar/SidebarItem.swift` | saiu | o painel da direita tem a peça própria (`InspectorTab`, feature inspector, plano 26); a barra virou a árvore (fase D) | 27 |
| arquivo | `apps/macos/features/sidebar/SidebarHeader.swift` | saiu | o painel da direita tem a linha de contexto própria (plano 26; fase D) | 27 |
| arquivo | `apps/macos/features/sidebar/SidebarView.swift` | saiu | a árvore do trabalho (`apps/macos/features/sidebar/WorkTreeView.swift`), com `SidebarCommands.swift` (fase D) | 27 |
| arquivo | `apps/macos/app/SidebarWiring.swift` | saiu | o catálogo do painel foi para `apps/macos/app/InspectorWiring.swift` (plano 26), a árvore para `apps/macos/app/TreeWiring.swift` e o Customize para `apps/macos/app/CustomizeWiring.swift` (fase B1) | 27 |
| comando | `sidebar.page-1` … `sidebar.page-9` | saiu | `inspector.tab-1` … `inspector.tab-4` (⌃⌘1 a ⌃⌘4, `apps/macos/app/InspectorWiring.swift`), fase D | 27 |
| comando | `sidebar.customize` | saiu | a árvore não se personaliza por ícones | 27 |
| comando | `sidebar.toggle-page` | saiu | as abas do painel da direita no ⌘K | 27 |
| chave | `sidebar.items` | saiu | a leitura, a escrita e a migração 4 saíram na fase D; um arquivo antigo com a chave abre sem aviso | 27 |
| gancho | `CADEX_PERF_SIDEBAR` | saiu | `CADEX_PERF_PANEL` abre a aba do painel e, com "agent-history", o Arquivo e histórico (fase D) | 27 |
| trecho | `sidebarPage` / aba "Sidebar" em `apps/macos/shared/customize/CustomizeWindow.swift` | saiu | sem personalizar ícones | 27 |
| spec | `docs/spec/sidebar.md`: "fileira de ícones" | saiu | a spec é a da árvore desde a fase B | 27 |

### Páginas da barra lateral
| tipo | peça | estado | destino | plano |
|---|---|---|---|---|
| arquivo | página files (`apps/macos/features/explorer/ExplorerOutline.swift` e a árvore) | muda | aba Arquivos do painel da direita | 26 |
| arquivo | página git (`apps/macos/features/source-control/SourceControlView.swift`) | muda | aba Mudanças do painel da direita | 26 |
| arquivo | página history (`apps/macos/features/git-history/HistoryCompactRows.swift`) | muda | aba Histórico do painel da direita | 26 |
| arquivo | página memory (`apps/macos/features/memory/MemoryView.swift`) | muda | aba Memória do painel da direita | 26 |
| comando | `git.show`, `git.show-history`, `memory.show`, `explorer.focus` | muda | abrem a aba do painel da direita | 26 |
| arquivo | página tasks (`apps/macos/features/worktrees/WorktreesView.swift`) | saiu | as tarefas na árvore (fase D) | 27 |
| comando | `worktrees.show` | saiu | sidebar.show mostra a árvore (plano 28 fase F) | 28 |
| arquivo | página agents: `apps/macos/features/agents/AgentsView.swift`, `apps/macos/features/agents/AgentSessionList.swift`, `apps/macos/features/agents/AgentsLayout.swift` | saiu | os agentes nos terminais da árvore; as sessões de fora do Cadex na página do projeto (plano 30); fase D | 27 |
| trecho | `pageShown` / `onWatching` em `apps/macos/features/agents/AgentsController.swift` e a leitura das máquinas em `apps/macos/app/RunOnWiring.swift` | muda | a página do projeto os chama enquanto aparece e mostra as sessões das outras máquinas entre as conversas, feito no plano 30 D | 30 |
| comando | `agents.show` | saiu | sidebar.show (⇧⌘J) mostra a árvore, onde estão os agentes (plano 28 fase F) | 28 |
| arquivo | página agent-history (`apps/macos/features/agents/AgentHistoryView.swift`, `AgentHistoryList.swift`) | muda | Arquivo e histórico, no centro: uma aba (`AgentHistoryDocument.swift`), feito na fase C | 27 |
| arquivo | página attention (`apps/macos/features/agents/AgentAttentionView.swift`) | muda | o conteúdo do popover do sino, feito | 26 |
| trecho | ".page(makeAttentionPage())" em `apps/macos/app/SidebarWiring.swift` | saiu | a página do sininho saiu da barra lateral; o id é aposentado em SidebarLayout.retired | 26 |
| comando | `agents.show-attention`, `agents.show-feed` | muda | abrem o sino | 26 |
| arquivo | página accounts (`apps/macos/features/agents/AgentAccountsView.swift`) | saiu | o popover da etiqueta de uso na barra de status (o clique numa conta abre o agente dela) e a página do projeto | 26 |
| comando | `agents.show-accounts` | muda | abre o popover de uso (sem o item na barra, a lista das contas no ⌘K), feito | 26 |

### Projetos (os spaces) (plano 27)
| tipo | peça | estado | destino | plano |
|---|---|---|---|---|
| arquivo | `apps/macos/features/spaces/` | saiu | a feature `projects` (`apps/macos/features/projects/`): o space com pasta; projects.json, migrado uma vez do spaces.json (fase A); a árvore na fase B | 27 |
| comando | `space.switch`, `space.new`, `space.rename`, `space.close`, `space.next`, `space.previous`, `space.set-color` | saiu | `project.*`; os apelidos saíram na fase F do 28 | 28 |
| trecho | "LegacySpaces" em `apps/macos/features/projects/ProjectsFile.swift` | saiu | a leitura do spaces.json, que virou projects.json uma vez no 27 (fase F do 28) | 28 |
| spec | `docs/spec/spaces.md` | muda | o Mac segue `docs/spec/projects.md` desde o plano 27; ela fica para o app do Windows, que ainda tem spaces (`docs/adr/0035-work-frame.md`: o Windows vem depois) | port |
| arquivo | `apps/macos/app/SpacesWiring.swift` | saiu | `apps/macos/app/ProjectsWiring.swift` | 27 |

### Terminal e painéis (plano 28)
| tipo | peça | estado | destino | plano |
|---|---|---|---|---|
| arquivo | `apps/macos/features/tabs/PaneHeaderView.swift` | muda | o cabeçalho com estado, conta, custo, tempo, feito na fase B (`apps/macos/app/PaneHeaderWiring.swift`) | 28 |
| chave | `tabs.paneHeaders` | saiu | cabeçalho sempre (o mockup mostra com um painel só); saiu na fase B, um arquivo antigo abre sem aviso | 28 |
| chave | `tabs.unfocusedDim` | saiu | os painéis sem foco a 92% do mockup (components.pane.idle); saiu na fase B, com a linha das configurações | 28 |
| trecho | "FocusOutlineView" em `apps/macos/features/tabs/PaneLayoutView.swift` | saiu | a sombra de antes sobre os painéis sem foco; a caixa de cada painel em `apps/macos/features/tabs/PaneChrome.swift` (fase B) | 28 |
| arquivo | `apps/macos/features/tabs/PaneLayoutView.swift` | muda | contorno de foco, vão de 8 pt, feito na fase B | 28 |
| arquivo | `apps/macos/features/terminal/TerminalAppearance.swift` | muda | respiro e cores afinadas: o respiro pela caixa do painel (fase B) e o ANSI do Cadex Night pelo que o Claude pinta no -ansi (fase C) | 28 |

### Entradas (plano 29)
| tipo | peça | estado | destino | plano |
|---|---|---|---|---|
| trecho | "confirmTask" em `apps/macos/app/WorktreesWiring.swift` | saiu | o fluxo de alertas do New Task: a folha única do ⌘N (`apps/macos/features/worktrees/NewTaskSheet.swift`), fase B | 29 |
| trecho | "askTaskName" em `apps/macos/app/RunOnWiring.swift` | saiu | o nome e o "Rodar em" num alerta: a máquina é uma linha de agente da folha, fase B | 29 |
| arquivo | `apps/macos/features/orchestration/NewRaceForm.swift` | saiu | a folha única do ⌘N (2+ agentes); as contas das folhas de execução e automação em `apps/macos/features/orchestration/AccountChoice.swift`, fase D | 29 |
| arquivo | `apps/macos/shared/customize/CustomizeWindow.swift` | saiu | a barra de status e as contas são seções das configurações (plano 32 B) | 32 |
| arquivo | `apps/macos/features/source-control/DiffDocument.swift` | saiu | o diff de um arquivo ou commit é a revisão aberta nele (plano 31 A) | 31 |
| comando | `diff.toggle-layout` | saiu | no Mac, com a aba de diff; o Windows ainda o tem até a moldura chegar lá | 31 |
| comando | `orchestration.new-race` | saiu | saiu no plano 30 D: a corrida pela folha Nova tarefa é worktrees.new-race | 30 |
| comando | `window.new` no ⌘N | muda | ⇧⌘N; o ⌘N é Nova tarefa, feito na fase A | 29 |

### Visão geral (plano 30)
| tipo | peça | estado | destino | plano |
|---|---|---|---|---|
| arquivo | `apps/macos/features/orchestration/RaceBoardView.swift`, `RaceColumns.swift` | muda | a corrida no centro, na cara nova; sem terminal aqui, uma página de cartões (OrchestrationPage), feito | 30 |
| arquivo | `apps/macos/features/orchestration/RunPageView.swift`, `RunRows.swift` | muda | o quadro com filtro de execução e a página da execução na cara nova (OrchestrationPage), feito | 30 |
| arquivo | `apps/macos/features/orchestration/AutomationHistory.swift` | muda | a página do projeto e Automações no pé da árvore; o histórico na cara nova, feito | 30 |

### Tema (plano 25)
| tipo | peça | estado | destino | plano |
|---|---|---|---|---|
| chave | `appearance.theme` padrão `caffeine` | muda | padrão `cadex-night`; arquivo sem versão no Caffeine passa uma vez (Settings.version 2) | 25 |
| arquivo | `apps/macos/features/themes/BuiltInThemes.swift` (Cadex Escuro e Claro, só os testes os usavam) | saiu | o Cadex Night gerado dos tokens (`apps/macos/features/themes/CadexNight.swift`), família própria no catálogo | 25 |

### Fica como está
`apps/macos/app/WindowBackdrop.swift` (imagem de fundo), `apps/macos/app/MenuBarItem.swift`, a
paleta ⌘K, `apps/macos/shared/menus/`, `apps/macos/shared/agent-band/`, `apps/macos/shared/icons/`,
os itens da barra de status (com cara nova no 26), a aba Status Bar e a aba Accounts do Customize.

### Windows
`apps/windows/app/chrome.zig` e `apps/windows/app/sidebar.zig` ficam com a casca velha até o plano
do Windows. Cada comando que sai do Mac sai também do `MAC_ONLY` de
`tools/check_command_parity.py` no mesmo plano.

### Cópias velhas
A worktree do plano 8 (`.claude/worktrees/`), com cópias antigas da casca, foi apagada com a branch
dela no plano 25 (o dono, 2026-11-17).

## Como validar
- `make manifests` roda `tools/check_leftovers.py`; toda linha `saiu` passa.
- Ao fim do plano 30, nenhuma linha está em `sai`.

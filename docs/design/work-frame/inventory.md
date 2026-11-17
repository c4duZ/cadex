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
| arquivo | `apps/macos/app/TitleBarButton.swift` | muda | o botão da barra nova | 26 |
| arquivo | `apps/macos/app/WorkspaceView.swift` | muda | as quatro regiões | 26 |
| arquivo | `apps/macos/app/PanelView.swift` | muda | o painel arredondado das fundações | 26 |
| comando | `space.switch` no botão da barra | sai | o botão de space sai; trocar de projeto pela árvore e ⌘J (plano 27/29) | 26 |
| comando | `power.toggle` no café da barra | muda | item da barra de status | 26 |
| comando | `app.check-for-updates` no botão da barra | muda | etiqueta na barra de status, só com versão nova | 26 |
| comando | `settings.open` no botão da barra | muda | só ⌘, e o menu | 26 |
| arquivo | `apps/macos/features/tabs/TabBarView.swift` | muda | as abas com estado na barra nova | 26 |
| arquivo | `apps/macos/features/tabs/TabAgentTitle.swift` | muda | vira a peça de estado das fundações | 25 |

### Barra lateral de ícones (planos 26 e 27)
| tipo | peça | estado | destino | plano |
|---|---|---|---|---|
| arquivo | `apps/macos/features/sidebar/SidebarIconRow.swift` | sai | a árvore do trabalho | 27 |
| arquivo | `apps/macos/features/sidebar/SidebarIconButton.swift` | sai | a árvore do trabalho | 27 |
| arquivo | `apps/macos/features/sidebar/SidebarSubtabs.swift` | sai | as sub-abas eram do sino (vira popover) | 26 |
| arquivo | `apps/macos/features/sidebar/SidebarLayout.swift` | sai | a árvore não tem ordem de ícones | 27 |
| arquivo | `apps/macos/features/sidebar/SidebarItem.swift` | muda | aba do painel da direita | 26 |
| arquivo | `apps/macos/features/sidebar/SidebarHeader.swift` | muda | cabeçalho das abas do painel da direita | 26 |
| arquivo | `apps/macos/features/sidebar/SidebarView.swift` | muda | a árvore do trabalho | 27 |
| arquivo | `apps/macos/app/SidebarWiring.swift` | muda | o catálogo do painel da direita e a árvore | 26 |
| comando | `sidebar.page-1` … `sidebar.page-9` | sai | apelidos das abas do painel no 26, saem no 27 | 27 |
| comando | `sidebar.customize` | sai | a árvore não se personaliza por ícones | 27 |
| comando | `sidebar.toggle-page` | sai | as abas do painel da direita no ⌘K | 27 |
| chave | `sidebar.items` | sai | migrada no 26 para a aba aberta do painel; leitura sai no 27 | 27 |
| gancho | `CADEX_PERF_SIDEBAR` | sai | `CADEX_PERF_PANEL` (aba do painel) e a árvore | 26 |
| trecho | `sidebarPage` / aba "Sidebar" em `apps/macos/shared/customize/CustomizeWindow.swift` | sai | sem personalizar ícones | 27 |
| spec | `docs/spec/sidebar.md`: "fileira de ícones" | sai | a spec da árvore | 27 |

### Páginas da barra lateral
| tipo | peça | estado | destino | plano |
|---|---|---|---|---|
| arquivo | página files (`apps/macos/features/explorer/ExplorerOutline.swift` e a árvore) | muda | aba Arquivos do painel da direita | 26 |
| arquivo | página git (`apps/macos/features/source-control/SourceControlView.swift`) | muda | aba Mudanças do painel da direita | 26 |
| arquivo | página history (`apps/macos/features/git-history/HistoryCompactRows.swift`) | muda | aba Histórico do painel da direita | 26 |
| arquivo | página memory (`apps/macos/features/memory/MemoryView.swift`) | muda | aba Memória do painel da direita | 26 |
| comando | `git.show`, `git.show-history`, `memory.show`, `explorer.focus` | muda | abrem a aba do painel da direita | 26 |
| arquivo | página tasks (`apps/macos/features/worktrees/WorktreesView.swift`) | sai | as tarefas na árvore | 27 |
| comando | `worktrees.show` | sai | apelido de mostrar a árvore no 27, sai no 28 | 28 |
| arquivo | página agents: `apps/macos/features/agents/AgentsView.swift`, `apps/macos/features/agents/AgentSessionList.swift`, `apps/macos/features/agents/AgentsLayout.swift` | sai | os agentes nos terminais da árvore; as sessões de fora do Cadex na página do projeto | 27 |
| comando | `agents.show` | sai | apelido no 27, sai no 28 | 28 |
| arquivo | página agent-history (`apps/macos/features/agents/AgentHistoryView.swift`, `AgentHistoryList.swift`) | muda | Arquivo e histórico, no centro | 27 |
| arquivo | página attention (`apps/macos/features/agents/AgentAttentionView.swift`) | muda | o sino em popover | 26 |
| comando | `agents.show-attention`, `agents.show-feed` | muda | abrem o sino | 26 |
| arquivo | página accounts (`apps/macos/features/agents/AgentAccountsView.swift`) | sai | o popover da etiqueta de uso na barra de status e a página do projeto | 26 |
| comando | `agents.show-accounts` | muda | abre o popover de uso | 26 |

### Projetos (os spaces) (plano 27)
| tipo | peça | estado | destino | plano |
|---|---|---|---|---|
| arquivo | `apps/macos/features/spaces/` | muda | a feature `projects`: o space com pasta, na árvore | 27 |
| comando | `space.switch`, `space.new`, `space.rename`, `space.close`, `space.next`, `space.previous`, `space.set-color` | sai | `project.*`; apelidos no 27, saem no 28 | 28 |
| spec | `docs/spec/spaces.md` | sai | `docs/spec/projects.md` | 27 |
| arquivo | `apps/macos/app/SpacesWiring.swift` | muda | `ProjectsWiring.swift` | 27 |

### Terminal e painéis (plano 28)
| tipo | peça | estado | destino | plano |
|---|---|---|---|---|
| arquivo | `apps/macos/features/tabs/PaneHeaderView.swift` | muda | o cabeçalho com estado, conta, custo, tempo | 28 |
| chave | `tabs.paneHeaders` | sai | cabeçalho sempre (o mockup mostra com um painel só); migrada no 28, sai no 29 | 29 |
| arquivo | `apps/macos/features/tabs/PaneLayoutView.swift` | muda | contorno de foco, vão de 8 pt | 28 |
| arquivo | `apps/macos/features/terminal/TerminalAppearance.swift` | muda | respiro e cores afinadas | 28 |

### Entradas (plano 29)
| tipo | peça | estado | destino | plano |
|---|---|---|---|---|
| trecho | o fluxo de alertas do New Task em `apps/macos/app/WorktreesWiring.swift` | sai | a folha única do ⌘N | 29 |
| arquivo | `apps/macos/features/orchestration/NewRaceForm.swift` | sai | a folha única do ⌘N (2+ agentes) | 29 |
| comando | `orchestration.new-race` | sai | apelido do ⌘N com 2 agentes no 29, sai no 30 | 30 |
| comando | `window.new` no ⌘N | muda | ⇧⌘N; o ⌘N é Nova tarefa | 29 |

### Visão geral (plano 30)
| tipo | peça | estado | destino | plano |
|---|---|---|---|---|
| arquivo | `apps/macos/features/orchestration/RaceBoardView.swift`, `RaceColumns.swift` | muda | a corrida no centro, na cara nova | 30 |
| arquivo | `apps/macos/features/orchestration/RunPageView.swift`, `RunRows.swift` | muda | o quadro com filtro de execução | 30 |
| arquivo | `apps/macos/features/orchestration/AutomationHistory.swift` | muda | a página do projeto e Automações no pé da árvore | 30 |

### Tema (plano 25)
| tipo | peça | estado | destino | plano |
|---|---|---|---|---|
| chave | `appearance.theme` padrão `caffeine` | muda | padrão `cadex-night` | 25 |
| arquivo | `apps/macos/features/themes/BuiltInThemes.swift` (Cadex Escuro e Claro) | muda | Cadex Night e o claro par dele; quem usava os velhos é migrado | 25 |

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

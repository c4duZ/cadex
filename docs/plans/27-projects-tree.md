# Plano 27 — Moldura nova (3/6): projetos e a árvore do trabalho

Depende de: plano 26 · Features: projects (a spaces renomeada), sidebar (vira a árvore), worktrees,
agents, tabs, command-palette · Decisões: `docs/adr/0035-work-frame.md` · Mockups: 2 (a árvore),
11 (a linha de tarefa e os estados), a peça Sidebar · Inventário: seções "Barra lateral de ícones"
(o resto), "Páginas da barra lateral" (tasks, agents, agent-history) e "Projetos".

## O que eu quero
- A esquerda vira a árvore do mockup: os projetos, os terminais de cada um, e as tarefas como
  grupos de terminais quando existem. Projeto é o space com pasta.
- Uso normal sem nunca ouvir "tarefa": abrir o projeto, um terminal com o Claude, e pronto.

## O que eu não quero
- Duas noções de grupo de abas: o space some como nome e como feature; fica o projeto.
- A página Tasks ou a página Agents vivas ao lado da árvore.
- A árvore lendo o disco ou o git a cada tecla: os mesmos avisos que as páginas de hoje já ouvem.

## Como eu quero
- Telas: Sidebar.dc.html (descritas em `docs/design/work-frame/screens.md`; cada uma implementada como a
  seção dela diz, e conferida lado a lado com o mockup).
- Tokens: components.sidebar (valores exatos em `docs/design/work-frame/tokens.json`).
- Cada arquivo reescrito entra na lista de tools/check_design_literals.py: só valores de
  `DesignTokens`, nada digitado.
- **A. Projetos.** Feita (2026-11-17): `apps/macos/features/projects/` (pasta por projeto, a raiz do
  repositório; a worktree de uma tarefa é do repositório principal), projects.json com a migração
  única do spaces.json (que fica ao lado como spaces.migrated.json), project.* com os space.* como
  apelidos, ProjectsWiring.swift; abrir com uma pasta faz o projeto dela; o daemon do terminal mantém
  o nome de antes (as sessões guardadas religam). A spec spaces.md fica para o app do Windows. Plano
  original: A feature `spaces` vira `projects` (pasta, spec docs/spec/projects.md, linha
  da tabela da raiz, `CLAUDE.md`): cada projeto tem a pasta do repositório, as abas, a cor e a
  ordem; o arquivo spaces.json é migrado uma vez para projects.json (um space sem pasta vira
  projeto da pasta do workspace dele). Comandos project.switch, project.new (abrir pasta),
  project.close, project.rename, project.next, project.previous, `project.set-color`; os
  `space.*` viram apelidos (saem no 28). SpacesWiring.swift vira ProjectsWiring.swift.
- **B. A árvore.** SidebarView.swift vira a árvore da peça Sidebar: "Nova tarefa ⌘N" e o filtro no
  topo; cada projeto dobrável (nome, branch, quantas tarefas); dentro, os terminais da pasta do
  projeto e as tarefas (worktrees) como grupos com a linha do mockup (`StateGlyph`, nome em negrito
  quando não lido, agente e conta, +/−, o que espera em âmbar, PR, idade); dentro do selecionado,
  os terminais dele. Clicar num terminal mostra a aba dele; no nome do projeto, a página do projeto
  (plano 30; até lá, os terminais dele). No pé: Automações e Arquivo e histórico. ⌘B recolhe.
  Adicionar projeto.
- **C. Arquivo e histórico.** Feita (2026-11-17, antes da B, para o histórico ter lugar quando a
  árvore tomar a coluna): agents.show-history abre "Archive & History" numa aba do centro
  (`apps/macos/features/agents/AgentHistoryDocument.swift`, a mesma página e as mesmas ações); a
  página saiu da barra lateral (o id em SidebarLayout.retired). Sem atalho: o ⌘⇧H do mockup é do
  preview web hoje, e o dono decide. Plano original: A página agent-history passa a abrir no centro, como documento, por
  Arquivo e histórico (⌘⇧H), com as mesmas ações (continuar, copiar o comando, revelar).
- **D. Remoção.** Saem: SidebarIconRow.swift, SidebarIconButton.swift, SidebarLayout.swift, a
  aba Sidebar do Customize, sidebar.customize, `sidebar.toggle-page`, os apelidos
  `sidebar.page-1…9`, a leitura de sidebar.items, a página Tasks (WorktreesView.swift) e a
  página Agents (AgentsView.swift, AgentSessionList.swift, AgentsLayout.swift), com
  worktrees.show e agents.show como apelidos de mostrar a árvore (saem no 28). As sessões dos
  agentes de fora do Cadex (o que a página Agents mostrava) passam para a página do projeto no 30:
  até lá, ficam no Arquivo e histórico, sem sumir. Specs, `CLAUDE.md`, `MAC_ONLY` e os cenários do
  `tools/perf/run.py` que usavam sidebar.items atualizados.
- **E. Varredura e fechamento.** Linhas do 27 em `saiu`; tools/find_unused.py; `make check`; `make
  perf` (a árvore com muitos projetos e tarefas); print ao lado dos mockups 2 e 11, e o dono vê.

## Como validar
- `make check` e `make perf` passam.
- Os spaces de antes voltam como projetos, com as abas, depois de reabrir.

# Plano 28 — Moldura nova (4/6): o terminal vestido e o preview ao lado

Depende de: plano 27 · Features: tabs (painéis), terminal, agent-tools (status line, kit), agents
(estado e permissões), preview, themes · Decisões: `docs/adr/0035-work-frame.md`,
`docs/adr/0018-element-picker.md`, `docs/adr/0023-answer-agent-permissions.md` · Mockups: 3
(terminais divididos), 3b e 3c (preview), 10 (o painel do Claude) · Inventário: seção "Terminal e
painéis" e os apelidos do 27.

## O que eu quero
- O painel do terminal como no mockup 10: o Claude Code continua sendo ele, mas na moldura, nas
  cores e no respiro do Cadex.
- O preview como painel ao lado de qualquer terminal, com um ou com vários.

## O que eu não quero
- Prometer o que o Claude desenha: o que é dele (a caixa da mensagem, as ferramentas) só muda de
  cor. Fase A mede antes.
- Cabeçalho que muda a cada tecla redesenhando a janela.

## Como eu quero
- Telas: Terminals.dc.html, PreviewOne.dc.html, PreviewMany.dc.html, Pane.dc.html (descritas em `docs/design/work-frame/screens.md`; cada uma implementada como a
  seção dela diz, e conferida lado a lado com o mockup).
- Tokens: components.pane, components.terminalTheme, components.preview (valores exatos em
  `docs/design/work-frame/tokens.json`).
- Cada arquivo reescrito entra na lista de tools/check_design_literals.py: só valores de
  `DesignTokens`, nada digitado.
- **A. Medir o Claude.** Numa instância de teste, com a conta de teste: quais cores o Claude Code
  manda (ANSI do tema ou cor fixa) no diff, na mensagem e nas ferramentas, em cada tema dele; qual
  tema o kit da sessão deve pedir para o nosso ANSI valer. Resultado escrito na spec do terminal.
- **B. O painel.** PaneHeaderView.swift na cara nova e sempre visível: `StateGlyph`, nome, tarefa,
  modelo, conta, custo e tempo (do que os hooks e o uso já sabem); o painel com foco com contorno e
  halo, os outros apagados; vão de 8 pt; respiro dentro do terminal. tabs.paneHeaders migrada uma
  vez (sai no 29).
- **C. Cores e status line.** O ANSI do Cadex Night afinado pelo que a fase A achou; a status line do
  kit (`core/features/agent-tools/statusline.zig`) em uma linha (modelo, contexto, custo, modo).
- **D. Marcas e permissão.** Marcas na barra de rolagem em cada mensagem do dono (âmbar onde o
  agente pediu algo); o pedido de permissão que chega pelo hook vira cartão no pé do painel com
  Permitir e Negar, o mesmo que o sino responde (responder num fecha o outro).
- **E. Preview ao lado.** Abre como painel ao lado do terminal que mostrou o endereço (a oferta de
  hoje, `onOpenPreview`), com a barra nova (endereço, Escolher elemento, tamanhos); o elemento
  escolhido entra na linha do agente como etiqueta. Um terminal só: terminal e preview lado a lado.
- **F. Remoção.** Saem os apelidos do 27 (`project.*` fica, `space.*`, worktrees.show e
  agents.show saem), a leitura de spaces.json, o cabeçalho velho e o escurecer velho que o novo
  substitui. Specs e `CLAUDE.md` de tabs, terminal, preview e agent-tools.
- **G. Varredura e fechamento.** Linhas do 28 em `saiu`; tools/find_unused.py; `make check`; `make
  perf` (terminal jorrando e TUI com o cabeçalho); prints ao lado dos mockups 3, 3b, 3c e 10, e o
  dono vê.

## Como validar
- `make check` e `make perf` passam.
- Um `claude` real (conta de teste, haiku) no painel novo, ao lado do mockup 10.

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
- **A. Medir o Claude.** Feita (2026-11-17): no tema padrão o Claude manda RGB fixo; no "dark-ansi" (por `--settings`), só ANSI; o kit pedirá o "-ansi" do modo do tema (`docs/spec/terminal.md`, As cores do Claude Code). Plano original: Numa instância de teste, com a conta de teste: quais cores o Claude Code
  manda (ANSI do tema ou cor fixa) no diff, na mensagem e nas ferramentas, em cada tema dele; qual
  tema o kit da sessão deve pedir para o nosso ANSI valer. Resultado escrito na spec do terminal.
- **B. O painel.** Feita (2026-11-17): caixas, vão, anel do foco, sem foco a 92%, respiro, o
  cabeçalho sempre e o que o app sabe do agente (`../../apps/macos/app/PaneHeaderWiring.swift`; o modelo vem do arquivo
  da sessão que a status line do kit grava); tabs.paneHeaders e tabs.unfocusedDim saíram já aqui.
  Plano original: PaneHeaderView.swift na cara nova e sempre visível: `StateGlyph`, nome, tarefa,
  modelo, conta, custo e tempo (do que os hooks e o uso já sabem); o painel com foco com contorno e
  halo, os outros apagados; vão de 8 pt; respiro dentro do terminal. tabs.paneHeaders migrada uma
  vez (sai no 29).
- **C. Cores e status line.** Feita (2026-11-17): o kit pede "dark-ansi" ou "light-ansi" pelo tema;
  o ANSI do Cadex Night afinado pelo que o Claude pinta no -ansi (91 a linha removida, 92 o ponto e a
  linha adicionada, 93 o trabalhando, 94 os destaques, 37 as bordas); a status line do kit é a
  linha do painel e a da conta não roda mais. Plano original: O ANSI do Cadex Night afinado pelo que a fase A achou; a status line do
  kit (`core/features/agent-tools/statusline.zig`) em uma linha (modelo, contexto, custo, modo).
- **D. Marcas e permissão.** Feita (2026-11-17): `TerminalScrollbar` com as marcas (Enter com agente;
  âmbar quando ele passa a esperar) e o polegar; o cartão de permissão no pé do painel pelo
  `footCard` do terminal, ligado à mesma atenção do sino. Plano original: Marcas na barra de rolagem em cada mensagem do dono (âmbar onde o
  agente pediu algo); o pedido de permissão que chega pelo hook vira cartão no pé do painel com
  Permitir e Negar, o mesmo que o sino responde (responder num fecha o outro).
- **E. Preview ao lado.** Feita (2026-11-17): a oferta do terminal abre o preview ao lado dele; a
  barra nova é o cabeçalho do painel (endereço com o ponto, Pick element, tamanhos); o contorno e a
  etiqueta do elemento no desenho do mockup. O elemento chega ao agente como um arquivo citado
  com `@` (a opção C2 do dono): uma linha curta na caixa, o bloco e o caminho do print no arquivo. Plano original: Abre como painel ao lado do terminal que mostrou o endereço (a oferta de
  hoje, `onOpenPreview`), com a barra nova (endereço, Escolher elemento, tamanhos); o elemento
  escolhido entra na linha do agente como etiqueta. Um terminal só: terminal e preview lado a lado.
- **F. Remoção.** Feita (2026-11-17): saíram os space.*, worktrees.show e agents.show (sidebar.show,
  ⇧⌘J, mostra a árvore e o "working" da barra o roda) e a leitura do spaces.json; o cabeçalho e o
  escurecer velhos já tinham saído na fase B. Plano original: Saem os apelidos do 27 (`project.*` fica, `space.*`, worktrees.show e
  agents.show saem), a leitura de spaces.json, o cabeçalho velho e o escurecer velho que o novo
  substitui. Specs e `CLAUDE.md` de tabs, terminal, preview e agent-tools.
- **G. Varredura e fechamento.** Linhas do 28 em `saiu`; tools/find_unused.py; `make check`; `make
  perf` (terminal jorrando e TUI com o cabeçalho); prints ao lado dos mockups 3, 3b, 3c e 10, e o
  dono vê.

## Como validar
- `make check` e `make perf` passam.
- Um `claude` real (conta de teste, haiku) no painel novo, ao lado do mockup 10.

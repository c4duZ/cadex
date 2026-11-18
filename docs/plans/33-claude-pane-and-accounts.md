# Plano 33 — O painel do Claude vestido de verdade e a troca de conta simples

Depende de: plano 32 · Features: terminal, agent-tools (kit, status line), agents (contas, uso,
atenção), tabs (cabeçalho do painel), memory (Continue in…) · Decisões: `docs/adr/0021-cadex-managed-accounts.md`,
`docs/adr/0028-project-memory.md`, `docs/adr/0035-work-frame.md` · Origem: o dono, 2026-11-18,
comparando o mockup Pane.dc.html com o dist: "tá extremamente diferente"; "pode tirar o
bonequinho e mexer no accept edits"; "para dentro do Claude, pode manter o padrão do Claude para
aceitar permissão"; "a gente só precisa pensar em formas de trocar essa conta de um jeito mais
simples"; "quando a pessoa tem o Dangerous Skip Permissions ativado nas configurações, todo claude
que ela digitar já vai ter".

## O que eu quero
- O painel do Claude o mais perto do mockup 10 que dá sem mexer no Claude: as cores do tema com o
  fundo do diff, a mensagem do dono discreta com cantos, a caixa de entrada arredondada, sem o
  mascote, o modo à direita da status line. A comparação de 2026-11-18 (mockup, hoje, caminho 1 e
  caminho 2, página local) é o alvo, com o caminho escolhido pelo dono: o diálogo de permissão do
  Claude fica.
- Trocar de conta num clique, levando o trabalho pela memória (o "Continue in…"): no cabeçalho do
  painel, no aviso de limite, no cartão de uso e no ⌘K.
- O `claude` digitado igual ao aberto pelo Cadex: a conta do projeto ou a ativa, e
  `--dangerously-skip-permissions` com a opção ligada.

## O que eu não quero
- Modificar o Claude: nada no programa dele, na configuração das contas ou no `~/.claude`. Tudo
  pelo `--settings` da sessão, pelo kit (hooks e status line) e pelo desenho do terminal.
- Esconder do Claude o que mostra uma escolha: o diálogo de permissão fica inteiro no painel.
- Reconhecer a tela do Claude sem a medida dos bytes de uma versão real, ou de um jeito que, se
  falhar, esconda coisa errada: falhando, a peça do Claude aparece como hoje.
- Compartilhar a pasta projects/ entre contas (ADR 0021): a troca leva o trabalho pela memória.

## Como eu quero
- **A. Medir.** Feita (2026-11-18, Claude Code 2.1.327, `docs/spec/terminal.md`, As cores e as
  formas do Claude Code): no "dark-ansi" o diff não tem fundo e a mensagem do dono cai no ANSI 8
  (o cinza claro do dist); no "dark" e no "light" tudo é cor fixa, medida numa tabela; o mascote,
  a caixa e a linha do modo têm forma reconhecível; o modo não chega na hora por hook nem pela
  status line (o ⇧⇥ não dispara hook, e o JSON da status line não o traz), só pela linha do modo.
  Plano original: Com um `claude` real (2.1.327, conta bkdg, Haiku) num terminal que grava cada
  byte, nos temas "dark" e "dark-ansi": o mascote (caracteres, linhas, cor), a linha do modo em
  cada modo, as duas linhas da caixa de entrada, os fundos da mensagem do dono e do diff, o ponto
  de uma ferramenta esperando; o `permission_mode` que os hooks recebem.
- **B. Cores.** Feita (2026-11-18): o kit pede "dark" ou "light"; `../../apps/macos/features/terminal/ClaudeDress.swift` troca as cores fixas medidas pelas tiradas do tema do terminal (o fundo, o texto e o ANSI), enquanto o Claude se reporta pelo OSC 7501. Plano original: O kit volta a pedir o tema de cores fixas do Claude ("dark" ou "light", pelo modo
  do tema do Cadex) e o terminal troca as cores fixas que o Claude usa pelas do tema
  (components.terminalTheme) enquanto o programa em frente é o `claude`: fundo e texto do diff,
  fundo da mensagem do dono, destaques, o trabalhando, o modo. Uma tabela na spec, conferida a
  cada versão do Claude que mudar uma cor.
- **C. Formas.** Feita (2026-11-18): o mascote não é desenhado; a caixa arredondada no lugar das duas linhas da entrada; a mensagem do dono num bloco com cantos; a linha do modo lida, não desenhada, e o modo à direita da status line; o ⏺ rodando âmbar; um tipo de quad novo no shader (retângulo arredondado, cheio ou contorno). Conferido no app com um `claude` real. Plano original: O terminal, enquanto o programa é o `claude`: não desenha o mascote (o texto ao
  lado fica); desenha a caixa arredondada no lugar das duas linhas da entrada; dá cantos e respiro
  ao fundo da mensagem do dono; lê o modo da linha do modo (a fase A mostrou que só ela o sabe
  na hora), não a desenha e põe o modo à direita da linha de cima, a status line; o ⏺ de uma
  ferramenta rodando fica âmbar. Linha que não reconhece fica como o Claude desenha. Seleção,
  busca e cópia continuam no texto de verdade.
- **D. Permissão.** Feita (2026-11-18): o cartão do pé do painel e o AgentPermissionCard saíram; o pedido chega pelo hook (o `cadex hook PermissionRequest` fica esperando) e o sino mostra Allow, Deny e Go to tab, conferido no app com um `claude` real; o cartão do painel falhava do lado do painel, que saiu. Plano original: O cartão "Wants to run…" sai do pé do painel (fica o diálogo do Claude) e
  continua no sino e no feed, para quem não está olhando o terminal. Conferir que o pedido chega
  pelo hook ao sino (no teste de 2026-11-18 o cartão não apareceu: achar o motivo).
- **E. Trocar de conta.** `agents.switch-account`: com um Claude em foco, encerra a sessão (o
  handoff vai para a memória) e abre no mesmo painel o "Continue in…" da conta escolhida; sem
  Claude em foco, abre a conta como hoje. Pontos de entrada:
  - a conta no cabeçalho do painel vira botão: a lista das contas com o uso de cada uma;
  - o aviso no pé do painel quando a conta bate o limite: "<conta> chegou ao limite · Continuar
    na <outra> (N% usado)", a de mais folga sugerida;
  - o clique numa conta no cartão de uso e "Switch account" no ⌘K.
- **F. O `claude` digitado.** Feita (2026-11-18): o kit leva `config_dir` (a conta) quando a aba não tem; `cadex claude` e `cadex continue` a põem no ambiente só sem uma da aba; a flag de permissões pela opção, menos com o modo na linha; a gaveta entra na conferência dos shells. Conferido no app (a conta ativa sem prefixo, a flag; a da aba mantida); a gaveta só pelo código. Plano original: Sem `CLAUDE_CONFIG_DIR` na linha, usa a conta do projeto, senão a
  ativa (como as sessões que o Cadex abre); com agents.launchSkipPermissions, ganha
  `--dangerously-skip-permissions`, a menos que a linha diga o modo (`--permission-mode`, a própria
  flag). O texto da opção diz "todo claude". Conferir o `claude` digitado na gaveta de terminais
  (o pedido do kit só aceita os shells das abas dos projetos).
- **G. Fechamento.** Specs (terminal, agents, agent-tools, memory), manifestos, `make check`,
  `make perf` (terminal jorrando e TUI com o desenho novo), o painel do dist ao lado do mockup e da
  projeção, conferido com um `claude` real.

## Como validar
- Testes do terminal com os bytes medidos na fase A: as cores trocadas, o mascote não desenhado,
  a caixa, a linha do modo escondida só com o kit; bytes de outra versão (uma palavra mudada)
  deixam tudo como o Claude desenha.
- Testes do kit: o `claude` digitado com e sem conta na linha, com e sem a opção de permissões, e
  com `--permission-mode` na linha.
- No app, com um `claude` real: o painel ao lado do mockup; trocar de conta pelos quatro caminhos e
  a sessão nova começando com o handoff; o aviso de limite (com um arquivo de uso falso).

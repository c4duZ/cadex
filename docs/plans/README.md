# Planos: do fim do terminal ao MVP no Mac, e o port para o Windows

Um plano por entrega que o dono abre e usa (os oito primeiros levam ao MVP no Mac; os seguintes,
nas tabelas abaixo). Cada plano é autocontido e dividido em fases que
cabem numa sessão. Escritos em 2026-10-19, quando o Cadex tinha o terminal funcionando numa janela
(shell num PTY, desenho em Metal, SF Mono nítido, teclado básico, edição estilo Mac com ⌥ e ⌘).

## O que eu quero
- Chegar ao MVP do Cadex no macOS: um app que o dono usa no dia a dia, leve,
  com código próprio e licença MIT.
- Executar nesta ordem; cada plano começa com o anterior concluído:

| # | plano | entrega | status |
|---|---|---|---|
| 1 | `docs/plans/1-terminal.md` | terminal completo | feito; falta conferência manual |
| 2 | `docs/plans/2-tabs-splits-palette.md` | abas, divisões e paleta ⌘K | feito |
| 3 | `docs/plans/3-window-and-theme.md` | janela, tema, configurações | feito; falta conferência manual |
| 4 | `docs/plans/4-files.md` | workspace, explorer e busca | feito; falta conferência manual |
| 5 | `docs/plans/5-viewers.md` | código, Markdown, mídia e preview web | feito; falta conferência manual |
| 6 | `docs/plans/6-git.md` | source control e grafo do git | feito; falta conferência manual |
| 7 | `docs/plans/7-mvp-release.md` | spaces que restauram, empacotamento, semana de uso | em andamento: fases A a D feitas; falta a semana de uso |
| 8 | `docs/plans/8-panes-with-documents.md` | documentos em painéis ao lado do terminal (v1.0) | feito, publicado na v1.0.0; falta conferência manual |

- Depois do Mac, o port para o Windows 11 (pedido do dono em 2026-10-19, todas as features), em Zig
  com Win32 e Direct3D 11 (`docs/adr/0012-windows-zig-win32-d3d11.md`), na mesma ordem:

| # | plano | entrega | status |
|---|---|---|---|
| 9 | `docs/plans/9-windows-core.md` | núcleo compilando e testado no Windows, ConPTY, WSL | B a H feitas; falta a VM (A) |
| 10 | `docs/plans/10-windows-terminal.md` | janela e terminal completo no Windows | escrito, compila; falta rodar na VM |
| 11 | `docs/plans/11-windows-shell.md` | abas, divisões, paleta, tema, configurações | escrito, compila; falta rodar na VM |
| 12 | `docs/plans/12-windows-files-viewers-git.md` | explorer, busca, visualizadores e git | escrito, compila e ligado no app; falta rodar na VM |
| 13 | `docs/plans/13-windows-release.md` | spaces, painéis com documentos, instalador e release | A a C escritas; falta a VM, medir (D) e a semana de uso (E) |

- Depois do port, nos dois apps (pedido do dono em 2026-10-20):

| # | plano | entrega | status |
|---|---|---|---|
| 14 | `docs/plans/14-languages-and-settings.md` | inglês por padrão, português como opção, configurações refeitas | feito; falta rodar no Windows e conferir à mão |
| 15 | `docs/plans/15-themes-and-personalization.md` | mais temas e personalização visual (claro/escuro, destaque, contraste, fonte, zoom, cores de space e aba) | fases A a D no código, Mac e Windows (2026-10-20); falta conferir à mão no Mac e no PC Windows |
| 16 | `docs/plans/16-element-picker.md` | escolher elemento no preview e mandar para o agente no terminal (só Mac) | fase A feita e conferida pelo dono (2026-10-21; falta ⇧, ⌥ e Esc à mão); B a D no código, falta conferir em projetos reais |
| 17 | `docs/plans/17-sidebar-agents-status.md` | barra lateral com ícones, página Agents (sessões e uso das contas), barra de status personalizável, SSH (só Mac) | feito (v2.2.0); o sinal do agente no título da aba veio no plano 19, fase B |

- Depois do 17, o Cadex dono da sessão do agente: o comportamento do Orca, a memória do AI Memory e
  as máquinas pelo Tailscale (pedido do dono em 2026-11-14, depois do estudo
  "Cadex × Claude Code"; o motor stream-json e o celular ficam para depois), nesta ordem:

| # | plano | entrega | status |
|---|---|---|---|
| 18 | `docs/plans/18-accounts-and-sessions.md` | contas em pastas do Cadex, configuração por link, uso sem token, histórico unificado e continuar em outra conta | feito (2026-11-14); falta o /login do dono numa conta nova (fase C) |
| 19 | `docs/plans/19-agent-sessions-and-worktrees.md` | worktree por tarefa, estado por hooks, quadro "Precisa de você", daemon do terminal, hibernar | feito (fases A a G); falta o dono ver no app: o Dock com uma instância só, o New Task pelo clique, a tela religada com keepSessions e a aba hibernada voltando |
| 20 | `docs/plans/20-agent-drives-cadex.md` | CLI `cadex` e skills, preview como navegador do agente, computer use | feito (2026-11-15): a CLI e o MCP, o navegador do agente, console, Design Mode e notas, computer use |
| 21 | `docs/plans/21-review.md` | diff de revisão, comentar no diff e mandar em lote, autoria por linha | feito (2026-11-15): o diff de revisão e o stage parcial, a aba de revisão, imagem e conflito, comentários mandados ao agente, autoria por linha |
| 22 | `docs/plans/22-memory.md` | memória: o engine do ai-memory (fork em Rust) no processo `cadex-memory`, nascendo ligada com embeddings, continuar em outro agente, consolidação sem token, página Memory | feito (2026-11-16): fases A a I: o engine nas sessões e no `claude` digitado, importação, memória automática do Claude, handoff de fatos, o .ai-memory.toml, a âncora depois da compactação, as ferramentas e as skills do ai-memory no kit, busca híbrida medida, continuar em outro agente (`cadex continue`, o `ai-memory run`), consolidação na sessão pelo próprio Claude com as regras do ai-memory e a manutenção por evento, o agente de memória (`claude -p` da conta como provedor do ai-memory, desligado, com teto), a página Memory e o peso no `make perf` (engine parado 13 MB, pico com o modelo abaixo de 400 MB e volta ao parado, hook abaixo de 1 ms); falta conferência manual (a página Memory e os comandos clicados no app, o Codex com conta) |
| 23 | `docs/plans/23-machines.md` | máquinas da tailnet, "Rodar em", Docker pela tailnet, ambiente descartável por worktree | fases A a H no código (2026-11-16): ADRs 0030 a 0032, as máquinas da tailnet no cartão do ssh (testado contra o Tailscale deste Mac), "Rodar em" por ssh, Docker por aba, a receita de ambiente, aceitar outras máquinas por WhoIs, compartilhar o preview, o peso no `make perf`; C a G testadas com ssh, docker, CLI e respostas falsas; falta conferir B a G com o PC na tailnet (e o `serve` com o dono) |
| 24 | `docs/plans/24-many-agents.md` | mesma tarefa em N agentes, orquestração, automações agendadas | fases A e B feitas (2026-11-16: ADRs 0033 e 0034, spec, a feature orchestration com o estado em SQLite); C feita (a corrida testada no app com o claude real, pela folha e pelo gancho de teste; falta o concorrente remoto com o PC); feito (2026-11-16): corrida, execuções com agentes que reportam pela CLI e portões, automações pelo launchd, o peso no `make perf`; testado no app com o claude real e agentes falsos; falta o concorrente remoto com o PC na tailnet, um sono de verdade do Mac e as folhas vistas a olho com o dono |

- Depois do 24, a moldura nova em seis planos, cada um tirando o que substitui (o dono, 2026-11-17: "muda tudo. Vamos tentar
  fazer isso… cuidado para não deixar cascas do que é hoje para trás"); o mapa da casca velha é
  `docs/design/work-frame/inventory.md`:

| # | plano | entrega | status |
|---|---|---|---|
| 25 | `docs/plans/25-work-frame.md` | fundações: specs, tema Cadex Night, medidas, a peça de estado, o inventário e a máquina contra casca velha | feito (2026-11-17): fases A a E; galeria de fidelidade em https://claude.ai/artifact/FpF42fpf4XMZoP4rZSmy37 |
| 26 | `docs/plans/26-frame.md` | barra de título, barra de status, painel da direita, o sino em popover | feito (2026-11-17): fases A a F; `make perf` passou com o painel aberto |
| 27 | `docs/plans/27-projects-tree.md` | projetos (os spaces) e a árvore do trabalho; sai a fileira de ícones | fechado (2026-11-17): fases A a E; a revisão de fidelidade contra os mockups renderizados e a moldura de novo no tema entraram junto |
| 28 | `docs/plans/28-dressed-terminal.md` | o terminal vestido e o preview ao lado | fechado (2026-11-17): fases A a G; o elemento escolhido chega ao agente como arquivo citado com @ (escolha do dono) |
| 29 | `docs/plans/29-entrances.md` | tela de início, a folha única do ⌘N (tarefa e corrida), ⌘J | escrito |
| 30 | `docs/plans/30-overview.md` | página do projeto, quadro, corrida, gaveta e a auditoria final | escrito |

## O que eu não quero
- Executar plano sem ler antes o `CLAUDE.md` da raiz e o da feature que vai mexer.
- Código de outro app como referência (ADR 0004): a fonte é a spec em `docs/spec/` e o que o dono
  descreve. Feature nova começa escrevendo a spec dela
  (`docs/spec/README.md` tem o modelo).
- Começar uma fase com a anterior pela metade, ou terminar uma fase sem commit.
- Inflar o MVP: o que não está nos planos entra depois, com plano próprio.

## Como eu quero
Começando uma sessão do zero:
1. Ler `CLAUDE.md` (raiz), este índice e o plano da vez. Os planos citam os arquivos que importam.
2. Ferramentas da máquina: Zig 0.16 em `~/.local/bin/zig` (a libghostty exige 0.16; não usar o do
   Homebrew), Swift 6 das Command Line Tools (sem Xcode) e, para o engine da memória, Rust pelo `rustup` em
   `~/.cargo/bin` (a versão vem do rust-toolchain.toml do crate; `docs/adr/0028-project-memory.md`).
3. Comandos: `make check` (manifestos + testes do núcleo + testes do app), `make run` (abre o app),
   `make core` (só a biblioteca).
4. Ver o app de verdade: com o app aberto, o id da janela sai de um programinha Swift que lista
   janelas com CGWindowListCopyWindowInfo (dono "Cadex"), e `screencapture -x -o -l <id> arquivo.png`
   tira o print para conferir visualmente.
5. Conferir no app sem roubar o teclado do dono, que pode estar usando a máquina: acionar comandos
   pelos itens de menu do processo (`tell application "System Events" to tell process "Cadex" to
   click menu item "Dividir à direita" of menu "Painéis" of menu bar 1`) e capturar a janela com
   `screencapture -l`, que funciona com ela atrás. Abrir o app para teste com `CADEX_BACKGROUND=1`, que
   mostra a janela sem ativar o app nem tomar o foco. Tecla simulada vai para o app que estiver na
   frente: só usar depois de conferir que é o Cadex, logo antes de cada envio. Em 2026-10-19 teclas
   de teste caíram no Chrome do dono.

Ao fim de cada fase: `make check` passando, commit pequeno, `CLAUDE.md` das features tocadas
atualizado (status, pontos de entrada, regras), spec com os critérios marcados. Ao fim de cada plano:
marcar o status na tabela acima.

## Como validar
- `make check` passa ao fim de cada fase.
- O MVP está pronto quando todos os critérios de aceite das specs das features do atlas
  (`CLAUDE.md` da raiz) estão marcados e o dono usa o Cadex uma semana como seu terminal.

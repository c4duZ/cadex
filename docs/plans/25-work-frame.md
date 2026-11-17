# Plano 25 — Moldura nova (1/6): fundações, specs e o mapa da casca velha

Primeiro de seis planos que trocam a casca inteira do app pela dos mockups (25 fundações, 26 a
moldura, 27 projetos e a árvore, 28 o terminal vestido e o preview, 29 entradas, 30 visão geral e
fechamento).

Depende de: planos 17 a 24 · Features: themes, tabs, settings e `apps/macos/shared/looks` ·
Decisões: `docs/adr/0035-work-frame.md`, `docs/adr/0008-phosphor-icons.md` · Referência visual:
`docs/design/work-frame/` (o canvas em https://claude.ai/artifact/USEjcwzEjAzLoJ16mBNtFo) · Mapa da
casca velha: `docs/design/work-frame/inventory.md`.

## O que eu quero
- O app de verdade igual aos mockups (o dono, 2026-11-17: "se ficar isso, é lindo… muda tudo. Vamos
  tentar fazer isso"), sem sobrar casca do que existe hoje ("a gente tem que tomar cuidado para não
  deixar cascas do que é hoje para trás").
- Antes de qualquer tela, o que todas usam: as specs reescritas, as cores, as medidas, a peça de
  estado, e a máquina que impede casca velha de ficar.

## O que eu não quero
- Cor, raio, vão, altura ou fonte fixos numa tela: tudo das fundações.
- Peça substituída sem linha no inventário, ou plano que termina com linha dele em `sai`.
- Apelido de comando ou leitura de chave velha vivendo mais de um plano.
- SF Symbols ou os glifos improvisados dos mockups: Phosphor.

## Como eu quero
**Os tokens: fonte única, tirada dos mockups.** `docs/design/work-frame/tokens.json` tem cada valor
dos mockups com nome: as cores do tema "Cadex Night" (superfícies, linhas, texto, os seis estados,
diff, etiquetas, halos, sombras), os tamanhos e pesos de fonte, entrelinhas, espaçamento de letra,
raios, espessuras, opacidade, sombras, a escala de espaços e, em `components`, as medidas de cada
peça (barra de título, aba, árvore, linha de tarefa, painel, cabeçalho, cartão de permissão,
popover, folha, quadro, corrida, página do projeto, tela de início, gaveta). A fonte da interface é
a do sistema (ADR 0035); o terminal mantém a dele.
- `tools/check_design_tokens.py` (no `make manifests`) garante, nos dois sentidos: todo valor dos
  mockups é token, todo token aparece num mockup, todo nome citado por uma peça existe, e toda peça
  está num destes seis planos (a linha "Tokens:" de cada um), sem plano citando peça que não existe.
- Mudar um token é mudar o mockup e o tokens.json juntos; o conferidor não deixa um sem o outro.
- O que nos mockups é exemplo, e não token, fica marcado no próprio arquivo: o Claude Code de hoje
  (mockup 10, lado esquerdo), a loja dentro do preview e os botões de janela do macOS.
- Igualados nos mockups em 2026-11-17, antes de virar token (eram valores diferentes para a mesma
  coisa): cabeçalho do painel 36 e 38 → 34; respiro do terminal 16×18, 16×20 e 12×14 → 14×16;
  mensagem do dono 5×9 → 6×10 e caixa de entrada 8×11 → 9×12; linha do cabeçalho do painel sem
  foco #1F2125 → #22252A; botão secundário #17191C → #1A1C20 e raio 8 → 7; título do sino 13,5 →
  13; o "+" em 15, 17 e 18 → 16 (vira ícone de 16); fundo atrás das telas 0,55 → 0,6; recuo da
  lista da anatomia 20 → 18.
- Telas: Map.dc.html, Anatomy.dc.html (descritas em `docs/design/work-frame/screens.md`; cada uma implementada como a
  seção dela diz, e conferida lado a lado com o mockup).
- Tokens: components.window, components.stateGlyph, components.button, components.theme (e todas as
  primitivas).

**Fases:**
- **A. Specs.** O dono aceita a ADR 0035. Reescritas antes do código, cada uma dizendo o que some:
  `docs/spec/sidebar.md` (a árvore do trabalho), `docs/spec/spaces.md` → docs/spec/projects.md,
  `docs/spec/tabs.md` (abas com estado; cabeçalho de painel sempre), `docs/spec/status-bar.md`,
  `docs/spec/workspace.md` (as quatro regiões), `docs/spec/agents.md` (o sino em popover; as
  páginas Agents, Accounts e History saindo), `docs/spec/worktrees.md` e
  `docs/spec/orchestration.md` (a folha única do ⌘N), `docs/spec/themes.md`, `docs/spec/power.md`
  e `docs/spec/updates.md` (fora da barra de título). Novas: docs/spec/inspector.md (o painel da
  direita), docs/spec/home.md (a tela de início). Linhas na tabela da raiz para as features
  novas (inspector, home; projects no lugar de spaces) e termos no `docs/CONTEXT.md` (Projeto,
  Árvore do trabalho, Painel da seleção, Tela de início, Gaveta).
- **B. A máquina contra casca.** Feita (2026-11-17): `tools/check_leftovers.py` com o `--self-test`
  no `make manifests`, e `tools/find_unused.py`, que achou cinco restos mortos de antes desta série
  (removidos; a lista começa zerada). A worktree velha do plano 8 (cópias antigas da casca) saiu, com a branch dela (o dono, 2026-11-17). tools/check_leftovers.py lê o inventário e falha em toda linha
  `saiu` que ainda existe (as regras estão no próprio inventário), no `make manifests`, com testes.
  tools/find_unused.py: lista tipos e funções Swift de `apps/macos/` que só aparecem no próprio
  arquivo, e textos `T(...)` repetidos ou sem uso; roda na varredura de cada plano (não falha o
  `make check`: é lista para olhar). As cópias velhas em .claude/worktrees/plan-8 saem, depois
  de o dono ver.
- **C. Tema e tokens no app, gerados.** Feita (2026-11-17). `tools/design/build_tokens.py` gera, de
  `docs/design/work-frame/tokens.json`, `apps/macos/shared/looks/DesignTokens.swift` (cores, fontes,
  pesos, entrelinhas, espaçamento de letra, raios, espessuras, opacidade, sombras em camadas e a
  escala de espaços, com o nome do token), um arquivo de peças por região da moldura
  (`apps/macos/shared/looks/DesignTokensChrome.swift`, DesignTokensColumns.swift,
  DesignTokensCenter.swift, DesignTokensPages.swift, cada um abaixo de 300 linhas) e o tema
  `apps/macos/features/themes/CadexNight.swift` (components.theme e components.terminalTheme, o
  ANSI só com cores dos tokens); `--check` no `make manifests` falha se o gerado não bater com o
  tokens.json. O Cadex Night é família própria no catálogo, a primeira e o padrão, só escura (os
  mockups não têm versão clara: o par claro vem com um mockup claro). Os "Cadex Escuro/Claro" de
  BuiltInThemes.swift saíram: nenhum tema escolhível os usava, só os testes. Como o settings.json
  grava também os padrões, o arquivo ganhou versão (Settings.version, 2): arquivo sem versão no
  Caffeine (o padrão antigo) passa uma vez para o Cadex Night; um tema escolhido fica. As medidas
  passam pelo zoom e pela densidade de `apps/macos/shared/looks/UILooks.swift` em quem as usa.
  `tools/check_design_literals.py` (no `make manifests`, com `--self-test`): nos arquivos da lista
  FRAME_FILES (cresce a cada plano, conforme cada arquivo é escrito ou reescrito para a moldura; ao
  fim do 30 cobre toda a casca), nenhuma cor em hex ou por componentes, raio, espaço, altura ou
  tamanho de fonte digitado: só `DesignTokens`.
- **D. A peça de estado.** Feita (2026-11-17). `apps/macos/shared/state-glyph/` (components.stateGlyph):
  `GlyphState` com os seis estados (com "em revisão", que só o quadro usava e a anatomia passou a
  mostrar), `StateGlyphLook` (cor, espessura por tamanho, halo, o anel aberto em cima e um quadro
  parado para quem desenha à mão) e `StateGlyphView` (camadas; o anel gira no servidor de desenho só
  enquanto pode ser visto e nunca com "Reduzir movimento"), nos tamanhos 7, 9, 10 e 14. Exceção à
  regra de `apps/macos/shared/CLAUDE.md` registrada lá. Nas abas, o sinal no lugar do ícone e o
  título em negrito quando terminou sem ser visto; os sinais de texto ◐ ● ✓ ✕ ☾ saíram de
  `apps/macos/features/tabs/TabAgentTitle.swift`. Snapshots: state-glyphs.png e tab-states.png.
- **E. Varredura e fechamento.** Feita (2026-11-17). Inventário: BuiltInThemes.swift saiu, o tema e
  a aba mudaram como dito; `tools/find_unused.py` zerado (os tokens gerados ficam fora da lista,
  porque os próximos planos é que os usam); `make check`. Fidelidade, numa galeria para o dono
  (https://claude.ai/artifact/FpF42fpf4XMZoP4rZSmy37): o app de teste abrindo no Cadex Night, os
  seis estados nos quatro tamanhos ao lado da Anatomy, e a barra de abas com os sinais. Diferença
  registrada: o contorno do parado no tamanho 14 tem 1,5 pt nos tokens e 2 pt no desenho da
  Anatomy; vale o token (os outros parados do mockup têm 1,5).

## Como validar
- `make check` passa, com tools/check_leftovers.py no `make manifests`.
- Os snapshots do `StateGlyph` e do tema batem com o mockup Anatomy.

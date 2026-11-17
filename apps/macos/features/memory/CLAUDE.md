# memory (app macOS)

## O que eu quero
- O que o app põe na memória do projeto (`../../../../docs/spec/memory.md`,
  `../../../../docs/adr/0028-project-memory.md`, plano `../../../../docs/plans/22-memory.md` fase C):
  os hooks da memória e o ambiente deles em toda sessão que o Cadex abre, pelo kit
  (`../../shared/session-kit/`), a pasta da memória automática do Claude por projeto, e o
  aquecimento do engine na primeira abertura de cada versão.
- Com memory.enabled desligada, nada disso: o app tira a parte do kit e não aquece.

## O que eu não quero
- Falar com o `cadex-memory` daqui: quem fala com o memory.sock é o cliente do núcleo
  (`../../../../core/features/memory/hook_client.zig`), que os hooks rodam.
- Os hooks da memória dependendo de agents.stateHooks: aquela chave é só dos hooks do app.
- Importar outra feature: o app (`../../app/MemoryWiring.swift`) liga esta ao kit e às configurações.

## Como eu quero
- `MemoryKit.swift`: `part` monta o `SessionKitPart` da memória: em `hooks`, um
  `cadex memory-hook <evento>` (5 s, sem matcher, então o PostToolUse pega toda ferramenta; o hook
  de autoria da revisão fica à parte e, numa edição, os dois rodam) em SessionStart,
  UserPromptSubmit, PostToolUse, PreCompact, PostCompact, SubagentStart, SubagentStop, Stop e
  SessionEnd; na `env`, `CADEX_MEMORY_BIN` (o engine, `findEngine`: Contents/Helpers no pacote,
  senão o build de debug do `make app` em `core/features/memory/server/target/debug`),
  `CADEX_MEMORY_DIR` (`folder`: Application Support/Cadex/memory, ou o CADEX_MEMORY_DIR do app numa
  instância de teste) e, só numa instância de teste (CADEX_SOCKETS_DIR, CADEX_SESSIONS_DIR no
  ambiente do app), `CADEX_MEMORY_SOCKET` e `CADEX_SESSIONS_DIR`. Com
  memory.shareAcrossAccounts desligada, o `perAccount` da parte põe `CADEX_MEMORY_WORKSPACE` com a
  chave da conta da sessão (`accountKey` do kit): cada conta grava e lê a sua workspace no engine.
  Em `pluginDirs`, o plugin com as skills do próprio ai-memory (`findPlugin`: Resources/memory-plugin
  no pacote, senão o que o `make app` escreve em `core/features/memory/server/target`, pelo
  `cadex-memory export-plugin`; plano 22 fase D).
  Com memory.consolidateInSession (fase F), a `env` leva `CADEX_MEMORY_CONSOLIDATE_AT` (o
  memory.consolidateAtContext). `requestConsolidation` deixa o pedido de "tarefa pronta" de uma
  sessão (`<memória>/consolidate/requests/<sessão>.ready`, 0600, só id simples), que o hook lê no
  Stop seguinte; `consolidateNowText` é o que o memory.consolidate-now cola.
  O `perSession` da parte, quando quem abre a sessão sabe a pasta dela, põe `autoMemoryDirectory`
  na pasta do projeto (`MemoryProject.swift`); sem pasta conhecida, fica a padrão do Claude.
- `MemoryAgent.swift` (fase G, ADR 0029): `Config` (o que o dono escolheu: ligado, teto por dia,
  aprovação, a conta padrão e as de cada projeto, o `claude`) e `write`, o `<memória>/agent.json`
  (0600) que o engine lê a cada trabalho; `appToken`, o token do próprio app na pasta de tokens
  (memory-agent.token, feito uma vez); `environment` e `run`, o `cadex memory-agent` fora da linha
  principal, com o JSON de volta; também o texto puro (o briefing) e o stdin (write-page).
- A aba Memory do painel da direita (fase H; plano 26 fase C2c, na cara do mockup Inspector,
  components.inspector.memory): `MemoryView.swift` (desligada, o texto e "Turn On"; ligada, "Search
  what this project knows" (memory.search), até 3 propostas com Approve/Reject, "LEARNED TODAY" com
  as páginas de hoje em cartões, "WIKI" com a árvore (os tipos na ordem do mockup, sem seta; o estado do engine e do agente na dica
  do rótulo) e a
  nota do briefing com "See the briefing"; só pede dados quando aparece; cada botão roda um comando
  pelo `run`), `MemoryParts.swift` (as peças: a busca, os rótulos, os cartões, a nota),
  `MemorySearch.swift` (a busca no ⌘K pelas páginas: título, tipo, caminho e resumo),
  `MemoryWikiOutline.swift` (a árvore: cada pasta uma linha de 28 com a marca do tipo, o nome e a
  contagem; o clique abre a página no Markdown; o menu tem Open the Session, Reveal in Finder e
  Delete Page), `MemoryWiki.swift` (a árvore lida da pasta da wiki: só .md, sem
  .git nem arquivos ocultos, pastas primeiro, páginas mais novas primeiro; o frontmatter e a origem:
  sessão, agente, hora), `MemoryData.swift` (o JSON do `overview`, do `status`, das `proposals` e o
  projects.json), `MemoryPageState.swift` (o que a página mostra e os textos do estado; os custos com
  as casas que importam) e `MemoryCommands.swift` (memory.show, memory.search, memory.show-briefing numa aba só de
  leitura, memory.reindex, memory.refresh, memory.enable, memory.approve e memory.reject com a lista
  das propostas no ⌘K; memory.show-history, os commits da wiki na aba do Git History).
- `MemoryProject.swift`: a regra da chave do projeto (a raiz do repositório principal lida dos
  arquivos `.git`: a worktree e a subpasta dão a do checkout principal; fora do git, a própria
  pasta; os 16 primeiros hex do SHA-256 do caminho), a mesma de
  `../../../../core/features/memory/server/src/project_key.rs`, com o mesmo valor fixado num teste
  de cada lado; `autoFolder` cria `<memória>/auto/[<conta>/]<chave>` (0700; a conta só com
  memory.shareAcrossAccounts desligada) e grava nela um project.json (`root`, `account`) com que o
  engine acha o projeto. Lê arquivos, sem chamar o git: roda a cada sessão aberta.
- `MemoryWarmUp.swift`: `start` roda `cadex-memory --warm --data-dir <pasta>` em segundo plano
  (QoS utility, saída em /dev/null) quando a versão do app difere da guardada no arquivo
  `warmed-version` da própria pasta da memória (não em UserDefaults: uma instância de teste, com
  outra pasta, dividia as preferências do app real e aquecia a pasta real; make perf,
  2026-11-16); guarda a versão só se o engine sai 0 (falhou, tenta na próxima abertura). No `make run` a versão é "0", aquecida uma vez também.

## Como validar
- `make macos-test` (MemoryTests): os 9 eventos e o comando de cada um, a `env` do pacote e a do
  `make run`, a workspace só sem compartilhar, os hooks com agents.stateHooks desligada, a parte
  retirada, a chave do projeto (o valor fixado igual ao do engine, worktree e subpasta no
  checkout principal, fora do git a pasta), o `autoMemoryDirectory` de uma sessão no repositório,
  na worktree, sem compartilhar e sem pasta, e o aquecimento uma vez por versão e só com saída 0
  (um engine falso em script).
- No app, sem sessão real: o `--settings` de uma sessão do kit
  (Application Support/Cadex/kit) traz os 9 hooks e a `env` da memória.

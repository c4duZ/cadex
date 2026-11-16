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
  O `perSession` da parte, quando quem abre a sessão sabe a pasta dela, põe `autoMemoryDirectory`
  na pasta do projeto (`MemoryProject.swift`); sem pasta conhecida, fica a padrão do Claude.
- `MemoryProject.swift`: a regra da chave do projeto (a raiz do repositório principal lida dos
  arquivos `.git`: a worktree e a subpasta dão a do checkout principal; fora do git, a própria
  pasta; os 16 primeiros hex do SHA-256 do caminho), a mesma de
  `../../../../core/features/memory/server/src/project_key.rs`, com o mesmo valor fixado num teste
  de cada lado; `autoFolder` cria `<memória>/auto/[<conta>/]<chave>` (0700; a conta só com
  memory.shareAcrossAccounts desligada) e grava nela um project.json (`root`, `account`) com que o
  engine acha o projeto. Lê arquivos, sem chamar o git: roda a cada sessão aberta.
- `MemoryWarmUp.swift`: `start` roda `cadex-memory --warm --data-dir <pasta>` em segundo plano
  (QoS utility, saída em /dev/null) quando a versão do app difere da guardada em
  memory.warmedVersion (UserDefaults); guarda a versão só se o engine sai 0 (falhou, tenta na
  próxima abertura). No `make run` a versão é "0", aquecida uma vez também.

## Como validar
- `make macos-test` (MemoryTests): os 9 eventos e o comando de cada um, a `env` do pacote e a do
  `make run`, a workspace só sem compartilhar, os hooks com agents.stateHooks desligada, a parte
  retirada, a chave do projeto (o valor fixado igual ao do engine, worktree e subpasta no
  checkout principal, fora do git a pasta), o `autoMemoryDirectory` de uma sessão no repositório,
  na worktree, sem compartilhar e sem pasta, e o aquecimento uma vez por versão e só com saída 0
  (um engine falso em script).
- No app, sem sessão real: o `--settings` de uma sessão do kit
  (Application Support/Cadex/kit) traz os 9 hooks e a `env` da memória.

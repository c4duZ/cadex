# spaces (app macOS)

## O que eu quero
- Grupos de abas com nome, alternáveis, restaurados com diretórios e layouts ao reabrir.

## O que eu não quero
- Perder o layout se o app fechar inesperadamente.
- Mexer no miolo das abas: os spaces usam a porta de entrada da feature tabs (`TabsController`,
  `snapshot()`, `restore(_:makeDocument:)`, `setShown`, `closeAll`).

## Como eu quero
- `SpacesController.swift` é a porta de entrada: cada space é um TabsController com nome; um aparece
  na janela (`onSwitch`, o app troca a vista e a barra de abas), os outros seguem rodando escondidos
  (`isShown` falso: não mudam o título nem pegam o teclado). Salva meio segundo depois de cada
  mudança (`onStateChange` das abas) e na hora ao sair; restaura em `start`. Sem `fileURL` (janela
  aberta pelo ⌘N, passageira) não lê nem grava nada: só a janela principal é salva. `closeAll()` ao
  fechar a janela: salva uma última vez e encerra os shells de todos os spaces. A última aba de um
  space fecha o space; a do último space fecha a janela.
- `SpacesFile.swift`: o JSON em Application Support/Cadex/spaces.json (gravação atômica), com os
  spaces, o ativo e a pasta do workspace. Arquivo ilegível vai para spaces.bad-<data>.json e o app
  começa do zero. CADEX_SPACES_FILE aponta para outro arquivo: conferir o app em teste não pode
  apagar os spaces do dono.
- Cada space guarda a cor de trabalho (`color` no spaces.json; `activeColor`/`setActiveColor`).
- Comandos em `SpacesCommands.swift`: space.switch (⇧⌘S, lista na paleta), space.new (⌃⌘N),
  space.rename, space.close, space.next (⌃⌘→), space.previous (⌃⌘←). O nome na barra de título roda
  space.switch.
- O app (`apps/macos/app/SpacesWiring.swift`) cria as abas de cada space, reabre os documentos
  salvos (arquivos que existem e o histórico do git, autorizando a pasta de novo) e devolve a pasta
  do workspace quando o app abre sem pasta.
- Spec: `docs/spec/spaces.md`. Status: pronto (plano 7, fase A).

## Como validar
- `make macos-test` passa: primeira abertura, salvar e restaurar igual, arquivo corrompido,
  novo/próximo/renomear/fechar.
- No app: `CADEX_SPACES_FILE=<arquivo de teste> CADEX_BACKGROUND=1`, Abas > Novo space, dividir,
  Cadex > Sair do Cadex, abrir de novo e conferir as abas, a divisão e o space ativo.

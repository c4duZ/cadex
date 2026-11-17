# projects (app macOS)

## O que eu quero
- Os projetos (`../../../../docs/spec/projects.md`; o que eram os spaces, plano 27): cada um é a
  pasta de um repositório com as abas abertas nela, um nome (o da pasta, renomeável) e uma cor,
  alternáveis e restaurados com pastas e layouts ao reabrir.

## O que eu não quero
- Perder o layout se o app fechar inesperadamente.
- Mexer no miolo das abas: os projetos usam a porta de entrada da feature tabs (`TabsController`,
  `snapshot()`, `restore(_:makeDocument:)`, `setShown`, `closeAll`).
- Dois projetos da mesma pasta: abrir a pasta de um que já existe vai para ele.

## Como eu quero
- `ProjectsController.swift` é a porta de entrada: cada projeto é um TabsController com nome, pasta
  (a raiz do repositório) e cor; um aparece na janela (`onSwitch`, o app troca a vista e a barra de
  abas), os outros seguem rodando escondidos (`isShown` falso). `open(folder:)` abre o projeto da
  pasta (o do repositório dela) ou mostra o que já existe; `rename` vazio volta ao nome da pasta.
  Salva meio segundo depois de cada mudança (`onStateChange` das abas) e na hora ao sair; restaura em
  `start` (sem nada salvo, o projeto da pasta de abertura). Sem `fileURL` (janela do ⌘N, passageira)
  não lê nem grava nada. `closeAll()` ao fechar a janela: salva uma última vez e encerra os shells;
  os que o daemon do terminal mantém (terminal.keepSessions) são soltos e seguem rodando (plano 19,
  fase E2). A última aba de um projeto fecha o projeto; a do último fecha a janela (a tela de início
  entra no plano 29).
- `ProjectsFile.swift`: o JSON em Application Support/Cadex/projects.json (gravação atômica), com os
  projetos (nome, pasta, abas, cor), o ativo e a pasta do workspace. Arquivo ilegível vai para
  projects.bad-<data>.json e o app começa do zero. CADEX_PROJECTS_FILE aponta para outro arquivo:
  conferir o app em teste não pode apagar os projetos do dono. O spaces.json de antes do plano 27
  virou projetos uma vez; essa leitura saiu no plano 28. `repositoryRoot`: o repositório de uma pasta pelos arquivos
  (`.git`; a worktree de uma tarefa pertence ao repositório principal), sem rodar o git.
- Comandos em `ProjectsCommands.swift`: project.switch (⇧⌘S, a lista na paleta com a pasta de cada
  um), project.new (⌃⌘N, Abrir projeto: a pasta pelo seletor do sistema), project.rename,
  project.close, project.next (⌃⌘→) e project.previous (⌃⌘←); os space.* de antes saíram no plano 28.
  project.set-color fica no app
  (`../../app/WorkColors.swift`).
- O app (`../../app/ProjectsWiring.swift`) cria as abas de cada projeto, reabre os documentos
  salvos e devolve a pasta do workspace quando o app abre sem pasta; o daemon do terminal mantém o
  nome que tinha com os spaces (do caminho do spaces.json), para religar as sessões.
- Status: plano 27 fase A no código (a feature, o arquivo, a migração e os comandos). A árvore da
  esquerda vem na fase B.

## Como validar
- `make macos-test` passa: primeira abertura, salvar e restaurar igual, arquivo corrompido, abrir
  pasta (nova e de um projeto que existe), próximo, renomear, fechar, a migração do spaces.json e o
  repositório de uma worktree.
- No app: `CADEX_PROJECTS_FILE=<arquivo de teste> CADEX_BACKGROUND=1`, abrir um projeto, dividir,
  sair e abrir de novo e conferir as abas, a divisão e o projeto ativo.

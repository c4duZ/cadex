# settings (app macOS)

## O que eu quero
- Janela de configurações e as preferências salvas, valendo para todas as janelas na hora.

## O que eu não quero
- Preferência guardada em mais de um lugar: tudo no settings.json, inclusive os atalhos.
- Esta feature aplicando preferências nas outras: ela guarda e avisa; o app liga cada uma.

## Como eu quero
- `Settings.swift`: o modelo (geral com general.openFiles, terminal, aparência, explorer, markdown, power, atalhos) e os limites da spec.
  `SettingsFile.swift`: lê o JSON campo a campo (campo errado volta ao padrão e vira aviso, o resto
  vale) e escreve, com a versão do arquivo (Settings.version); `migrate` leva um arquivo antigo aos
  padrões novos uma vez (versão 2: do Caffeine ao Cadex Night, ADR 0035). `SettingsStore.swift`: memória e disco (Application Support/Cadex), salva a cada
  mudança e relê edição à mão observando a pasta (salvar atômico) e o arquivo (edição no lugar). CADEX_SETTINGS_FILE
  aponta para outro arquivo (os cenários do `make perf`).
- A janela (⌘,, comando settings.open): `SettingsWindowController.swift`, desde o plano 32 com as
  seções numa lista à esquerda e a busca em cima (`SettingsNavigation.swift`; as seções em
  `SettingsSections.swift`; as linhas de cada uma, que eram uma página Geral só, em `SectionRows.swift`, (em Agentes e contas, a seção Computer use: ligar, os apps já permitidos com Esquecer todos e o atalho para Privacidade e Segurança; o dono não a achava, 2026-11-20)
  a busca pelas palavras de cada linha, `SettingsRowBox`); a barra de status e as contas (as listas
  do antigo Personalizar, `customizePages`, dadas pelo app) são seções daqui; auxiliar de tela cheia (com o app em tela cheia, abre por cima dele, na mesma
  mesa, e não numa mesa à parte); `GeneralPages.swift` (About), `TerminalPage.swift` (com as notificações dos programas e manter
  os terminais quando o Cadex fecha, plano 19), `KeepAwakeRows.swift` (as seções do manter acordado em General), `MemoryRows.swift` (a seção
  Memória em General: memory.enabled e memory.shareAcrossAccounts; ao lado do SSH, machines.tailscale, plano 23), `OrchestrationRows.swift` e `OrchestrationSettings.swift` (a seção Muitos agentes:
  orchestration.*, desligadas por padrão, os números com limite ao ler; plano 24), `ThemesPage.swift` (modo, seus temas,
  busca e filtro claro/escuro, a grade e a moldura), `ThemeGrid.swift` (os cartões, só das linhas na
  tela, reaproveitados ao rolar), `ThemeActions.swift` (comandos theme.choose, -dark e -light com a lista no ⌘K,
  theme.import, theme.open-folder, theme.mode-system/-dark/-light, theme.accent, theme.accent-reset,
  theme.toggle-high-contrast; a página usa as mesmas ações), `ThemeLooksRows.swift` (escuro e claro,
  destaque com o `AccentPicker`, alto contraste, painéis sem foco), `TerminalTextRows.swift` (a seção
  Leitura do terminal), `NotificationRows.swift` (as notificações dos agentes em General: o som de cada tipo, que toca
  ao escolher, e a chave), `InterfaceRows.swift` (zoom, densidade e fonte da interface em General: valem
  ao reabrir, pergunta "Reabrir agora"); a janela registra settings.open-terminal,
  settings.open-themes e terminal.toggle-ligatures (`pageCommands`), `ShortcutsPage.swift` (grava a próxima combinação com os atalhos do
  app suspensos; Delete tira, Esc cancela, "Padrão" volta) e `SettingsPage.swift` (linhas, títulos de
  seção, notas, caixas e controles que mudam o arquivo na hora; a chave é o `ThemeSwitch` de
  `../../shared/customize/`, a mesma do Customize, pedido do dono em 2026-10-21). A cara da moldura
  desde o plano 31 D: o título e as linhas da página do projeto, os rótulos de seção da Nova
  tarefa, os popups e campos na caixa da moldura (`FrameField`), os botões do app, a chave nas cores
  da chave da página do projeto e as seções em pílulas no topo (`FramePill`). Textos em par inglês/português
  (`T`, `../../shared/strings`); trocar o idioma pergunta "Reabrir agora" e chama `relaunch`, do app. A janela segue o tema (`SettingsColors.swift`, os tokens da moldura): a página
  aberta se refaz com as cores novas, mantendo a rolagem, e a navegação, feita uma vez, é repintada
  (DesignTokens.repaint) ao abrir e a cada troca de tema ou de opacidade (DesignTokens.didChange). O
  fundo da janela é sólido mesmo com a janela principal translúcida (DesignTokens.solid).
- O app (`../../app/SettingsBridge.swift`) passa as preferências ao `TerminalPreferences` do
  terminal, ao tema e aos atalhos, e salva o que um alerta desliga ("não perguntar de novo").
- Spec em `../../../../docs/spec/settings.md`. Status: arquivo, store, aplicação ao vivo e janela
  prontos, com imagem de fundo (copiada para Application Support/Cadex/backgrounds) e vibrância.

## Como validar
- `make macos-test` passa: ler, escrever, arquivo quebrado, campo errado, limites, edição à mão, a
  página de temas com cartões só na tela. Com CADEX_SNAPSHOT_DIR, o teste salva um PNG da página
  (para ver sem captura de tela).

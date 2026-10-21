# settings (app macOS)

## O que eu quero
- Janela de configurações e as preferências salvas, valendo para todas as janelas na hora.

## O que eu não quero
- Preferência guardada em mais de um lugar: tudo no settings.json, inclusive os atalhos.
- Esta feature aplicando preferências nas outras: ela guarda e avisa; o app liga cada uma.

## Como eu quero
- `Settings.swift`: o modelo (geral com general.openFiles, terminal, aparência, explorer, markdown, power, atalhos) e os limites da spec.
  `SettingsFile.swift`: lê o JSON campo a campo (campo errado volta ao padrão e vira aviso, o resto
  vale) e escreve. `SettingsStore.swift`: memória e disco (Application Support/Cadex), salva a cada
  mudança e relê edição à mão observando a pasta (salvar atômico) e o arquivo (edição no lugar). CADEX_SETTINGS_FILE
  aponta para outro arquivo (os cenários do `make perf`).
- A janela (⌘,, comando settings.open): `SettingsWindowController.swift`, com as seções em abas no
  topo como no Terax, auxiliar de tela cheia (com o app em tela cheia, abre por cima dele, na mesma
  mesa, e não numa mesa à parte); `GeneralPages.swift` (General e About), `TerminalPage.swift`, `KeepAwakeRows.swift` (as seções do manter acordado em General), `ThemesPage.swift` (modo e
  grade de cartões de tema), `ShortcutsPage.swift` (grava a próxima combinação com os atalhos do
  app suspensos; Delete tira, Esc cancela, "Padrão" volta) e `SettingsPage.swift` (linhas, títulos de
  seção, notas, caixas e controles que mudam o arquivo na hora). Textos em par inglês/português
  (`T`, `../../shared/strings`); trocar o idioma pergunta "Reabrir agora" e chama `relaunch`, do app. A janela segue o tema (`SettingsColors.swift`): a página
  aberta se refaz com as cores novas, mantendo a rolagem.
- O app (`../../app/SettingsBridge.swift`) passa as preferências ao `TerminalPreferences` do
  terminal, ao tema e aos atalhos, e salva o que um alerta desliga ("não perguntar de novo").
- Spec em `../../../../docs/spec/settings.md`. Status: arquivo, store, aplicação ao vivo e janela
  prontos, com imagem de fundo (copiada para Application Support/Cadex/backgrounds) e vibrância.

## Como validar
- `make macos-test` passa: ler, escrever, arquivo quebrado, campo errado, limites, edição à mão.

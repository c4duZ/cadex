# app — entrada do app macOS

## O que eu quero
- Só o ponto de entrada: criar o NSApplication, as janelas e ligar as features.
- Várias janelas (⌘N, window.new): cada uma com workspace, spaces, explorer, busca, git e comandos
  próprios; só a principal (a que abriu com o app) salva os spaces (docs/spec/workspace.md).

## O que eu não quero
- Lógica de feature aqui. Cada coisa que a janela mostra vem de uma feature, pela porta de
  entrada dela (os tipos `public` do módulo).

## Como eu quero
- `PaletteWiring.swift`: a paleta nas cores do tema, os prefixos do ⌘K (`/` arquivos, `#` texto,
  `@` abas e spaces) e as aberturas (`openers`), primeiro no ⌘K e no menu do "+" das abas.
  Comando novo que abre algo (terminal, arquivo, web, janela) entra nos `openers` daqui e nos de
  `../../windows/app/app_commands.zig`, e na lista "Abrir" de `../../../docs/spec/command-palette.md`.
- `SpacesWiring.swift`: os spaces na janela (abas de cada space ligadas à barra de status e ao
  preview, documentos reabertos, pasta do workspace devolvida); `tabs` da `WindowSession` é sempre a
  do space que aparece, então os comandos agem nela. Janela aberta pelo ⌘N tem spaces sem arquivo.
- `FolderFollow.swift`: o workspace segue o terminal com foco; a cada `cd` vai para a raiz do
  repositório git da pasta (ou a própria pasta), a menos que explorer.followTerminal desligue.
- Antes de montar qualquer tela, `main.swift` define Strings.language pelo general.language (ADR
  0015); "Reabrir agora" nas configurações e a atualização (`startUpdates`) saem como de costume e um
  shell abre o Cadex de novo (`openAgain`), levando as variáveis CADEX_ (uma instância de teste
  reabre em segundo plano, com o arquivo de spaces dela).
- `main.swift` (AppDelegate) guarda o que as janelas dividem: configurações, a janela de
  configurações, o keymap e o despachante de atalhos, que trocam para os comandos da janela com
  foco (`sessionBecameKey`). Abre a janela principal e as do ⌘N (`newWindow`, na pasta da janela de
  onde veio, deslocada um passo). Sair pergunta uma vez pelos programas e arquivos de todas as
  janelas.
- `WindowSession.swift`: uma janela. Cria o `WorkspaceFolder`, o explorer, a busca, o git e os spaces
  dela; como delegate da janela pergunta às abas antes de fechar (shouldCloseAll) e, fechada,
  encerra os shells dela (`closeAll`). `SessionCommands.swift` registra os comandos de cada feature
  no registro da janela (e window.new, view.toggle-sidebar e git.show da casca) e liga a barra de
  status ao terminal com foco. Pastas e arquivos da linha de comando ou soltos no ícone do Dock
  (`application(_:open:)`, o Dock só com o pacote .app do plano 7): pasta vira workspace, arquivo
  abre numa aba, endereço http(s) abre no preview. `FileOpener.swift` decide o que abre (mídia pelo
  tipo, o resto no editor; diffs do git num DiffDocument, o histórico num HistoryDocument que recebe
  as mudanças em .git, páginas web num PreviewDocument) e onde: ao lado do painel com foco ou em
  nova aba, por general.openFiles (opensBeside em `SettingsBridge.swift`), ou pela escolha do explorer; quem
  pede (o histórico abrindo um diff) fica no painel dele. `makeDocument(identity:)` refaz os
  documentos salvos nos spaces. O elemento escolhido num preview vai por `ElementPickDelivery.swift`:
  colado sem Enter no terminal do agente, que ganha o foco, ou copiado (⌥, preview.pickTarget em
  `SettingsBridge.swift`, ou nenhum agente). Passa as mudanças do disco aos documentos abertos e monta a aparência do editor (`EditorLooks`).
- A casca da janela: título transparente com barra de ferramentas compacta
  (38 pt, botões da janela centrados); `TitleBarView.swift` (um grupo à esquerda com painel
  lateral, busca/paleta "⌘K" e spaces, o space só o ícone de pilha com um space e o nome com mais;
  o café do manter acordado antes do space (cheio ligado, contorno desligado; o clique roda
  power.toggle, o ⇧⌘A); depois as abas, "+" e, à direita, o botão de atualização (na cor de
  destaque do tema, só com versão nova para instalar; roda app.check-for-updates) e as
  configurações; cada controle um `TitleBarButton.swift` de
  26 pt com fundo ao passar e ao clicar,
  busca, todos por comando), `WorkspaceView.swift` (painéis arredondados de `PanelView.swift`,
  painel lateral recolhível, barra de status) e `SidebarWiring.swift` (o catálogo da feature `sidebar`: a árvore do explorer, o painel do git e o histórico compacto como páginas, a busca como ação; salva sidebar.items e põe a contagem de mudanças no ícone do Git; `openCustomize` abre a janela
  Customize única na aba pedida, com as abas da barra lateral e da barra de status desta janela, nas
  cores do tema como as configurações e não nas da janela, e a repinta quando o tema muda) e
  `StatusBarWiring.swift` (os itens Git branch e Terminals, e os lados salvos). `AgentsLaunch.swift`:
  esconder contas guardando o login, a aba Accounts do Customize e o clique numa conta: o agente dela
  já rodando num terminal do Cadex vem para a frente (o usado por último, em qualquer janela); sem
  nenhum, abre no terminal com foco (no prompt) ou numa aba nova. O explorer é criado
  junto com os comandos, antes de as configurações montarem os atalhos.
  As cores vêm do tema; a cor da moldura vai na janela, não numa camada da view, porque uma
  camada pintada cobria os botões da janela.
- Tela cheia: a barra de ferramentas (vazia, só dá a altura da barra de título) some ao entrar e
  volta ao sair, porque o macOS a punha numa faixa por cima da barra do app. Tamanho mínimo da
  janela 480×300.
- `WorkColors.swift` (plano 15, fase D): as cores de space e de aba pelo nome, desenhadas com o ANSI
  do tema; registra space.set-color e tab.set-color (lista no ⌘K) e põe a cor da aba ativa, ou a do
  space, no lugar do destaque da janela (workColor do WorkspaceView). O clique direito numa aba e no
  botão do space mostra `tabActions`/`spaceActions` (`PaletteWiring.swift`). `main.swift` chama
  UILooks.configure com o zoom, a densidade e a fonte da interface antes de qualquer tela.
- `MenuBarItem.swift`: o símbolo do Cadex na barra de menus do macOS (NSStatusItem), desenhado por
  `CadexMark.swift` com os caminhos do `docs/cadex-icon.svg`, branco com o manter acordado
  ligado, com a chama (fire-simple do Phosphor fill) saindo do braço de cima do >, e cinza desligado (o logo cheio nos dois); o clique roda power.toggle.
- `WindowBackdrop.swift`: imagem de fundo atrás da área do terminal (desfoque calculado uma vez) e,
  com vibrância, a moldura fosca; depois de ligar, os botões da janela voltam para cima da camada.
- Sem pacote .app (make run), `main.swift` põe o ícone de `docs/cadex-icon.png` no Dock; no .app ele
  vem do AppIcon.icns.
- Abrir para teste com CADEX_BACKGROUND=1: a janela aparece sem tomar o foco do teclado. Abas, spaces e a paleta
  entram aqui conforme as features existirem.
- Barra de título, botões dela, painel lateral e as abas dele medem por UILooks (`../shared/looks/CLAUDE.md`); a barra de título leva o zoom e não a densidade, porque o macOS põe os botões da janela.

## Como validar
- `make app` compila; `make run` abre a janela com um shell.

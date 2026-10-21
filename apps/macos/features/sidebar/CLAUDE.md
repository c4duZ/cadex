# sidebar (app macOS)

## O que eu quero
- A coluna à esquerda com uma fileira de ícones no topo, que escolhe a página, e quem usa decidindo
  quais ícones aparecem e em que ordem (`../../../../docs/spec/sidebar.md`, plano 17 fase A).

## O que eu não quero
- Esta feature conhecendo o explorer, o git ou qualquer outra: o app monta o catálogo com a view de
  cada uma, pela porta de entrada dela.
- Clique que faz a ação por conta própria: todo ícone roda um comando pelo id (ADR 0005).
- A ordem guardada em outro lugar que não o sidebar.items do settings.json.

## Como eu quero
- `SidebarItem.swift`: um item do catálogo (id, ícone Phosphor, título, comando, atalho para a dica);
  página (com view) ou ação (só roda o comando, como Search e History).
- `SidebarLayout.swift`: as regras puras e testadas: a lista salva contra os ids conhecidos (id
  desconhecido ou repetido sai e vira aviso), mostrar/esconder, mover, a ordem do painel, onde cai
  o ícone arrastado e quantos cabem antes do "…".
- `SidebarView.swift`: a porta de entrada. A fileira, o título da página (o nome da pasta em Files,
  `setTitle`) e as páginas; `setItems` recebe o sidebar.items, `onItemsChange` devolve o que mudou
  para o app salvar, `setBadge` põe a contagem ou o ponto num ícone. Clicar no ícone da página
  aberta roda view.toggle-sidebar.
- `SidebarIconRow.swift` e `SidebarIconButton.swift`: os ícones; arrastar para o lado reordena
  (depois de 4 pt), o que não cabe vai para o "…" (menu de `../../shared/menus`), o botão de
  personalizar fica à direita.
- Personalizar: a aba Sidebar (`customizePage`) da janela única de `../../shared/customize/`, que o
  app abre (`onCustomize`, sidebar.customize): o título "Sidebar icons" e todas as páginas, as que
  aparecem primeiro; o que volta dela vira sidebar.items.
- A fileira fica sob a barra de título transparente: nenhuma view dela move a janela
  (mouseDownCanMoveWindow). O que se arrasta vai para cima dos vizinhos e anda a partir de onde
  estava no começo; a vaga é a que está sob o meio dele (CustomizeLayout.dropIndex).
- `SidebarCommands.swift`: sidebar.customize, sidebar.toggle-page (a lista de páginas no ⌘K) e
  sidebar.page-1 a -9 (⌃⌘1 a ⌃⌘9): o ícone na posição, como um clique nele (`press(position:)`);
  ⇧⌘3 a ⇧⌘5 são as capturas de tela do sistema, por isso ⌃⌘ (o dono, 2026-10-21).
- O catálogo do app está em `../../app/SidebarWiring.swift`: files, search, git, agents, accounts
  (padrão) e history (escondido). Só entra o que mostra uma página na barra; preview e spaces saíram (o dono,
  2026-10-21). `onShow` avisa quando uma página aparece, para o app só criar o conteúdo então.
- Status: fase A no código. Ainda não: sub-abas (chegam com Agents na fase C) e a página aberta
  voltando com os spaces.

## Como validar
- `make macos-test` passa: o arrastar dos ícones com eventos de mouse (uma vaga, duas, o arrastado por
  cima), a lista que vai para o Customize, as regras do layout, a view mostrando a primeira página, o clique que
  roda o comando ou recolhe, mostrar/esconder salvando. Com CADEX_SNAPSHOT_DIR, o teste salva
  sidebar.png e sidebar-narrow.png para ver sem captura de tela.

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
- `SidebarCustomizePanel.swift`: a janela Customize, na frente do app e centrada sobre ele, como a de
  configurações, nas cores do tema (o dono recusou o popover do sistema e depois o cartão preso ao
  botão, em 2026-10-21); fecha com Esc, ⌘W ou o botão. `SidebarCustomizeRows.swift`: as linhas em
  caixas (alça, ícone, nome, atalho numa coluna fixa, chave própria na cor de destaque) e o arrastar
  para cima e para baixo, que reorganiza enquanto o mouse se move.
- A fileira fica sob a barra de título transparente: nenhuma view dela move a janela
  (mouseDownCanMoveWindow). O que se arrasta vai para cima dos vizinhos e anda a partir de onde
  estava no começo; a vaga é a que está sob o meio dele (`dropIndex`).
- `SidebarCommands.swift`: sidebar.customize e sidebar.toggle-page (a lista de páginas no ⌘K).
- O catálogo do app está em `../../app/SidebarWiring.swift`: files, search, git (padrão) e history
  (escondido). Só entra o que mostra uma página na barra; preview e spaces saíram (o dono,
  2026-10-21). `onShow` avisa quando uma página aparece, para o app só criar o conteúdo então.
- Status: fase A no código. Ainda não: sub-abas (chegam com Agents na fase C) e a página aberta
  voltando com os spaces.

## Como validar
- `make macos-test` passa: o arrastar com eventos de mouse (uma vaga, duas, a lista do Customize
  reorganizando antes de soltar, o arrastado por cima), as regras do layout, a view mostrando a primeira página, o clique que
  roda o comando ou recolhe, mostrar/esconder salvando. Com CADEX_SNAPSHOT_DIR, o teste salva
  sidebar.png, sidebar-narrow.png e customize.png para ver sem captura de tela.

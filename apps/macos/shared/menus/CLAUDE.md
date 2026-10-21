# menus (compartilhado do app)

## O que eu quero
- Os menus que abrem por cima do app (clique direito, o "+" das abas, as pastas da barra de status)
  com a cara do ⌘K: cores do tema, ícones Phosphor, seleção arredondada e atalhos como teclas. O
  menu do sistema era translúcido e destoava do resto (o dono, 2026-10-20).

## O que eu não quero
- `NSMenu` em menu que abre pelo clique: só a barra de menus do macOS continua do sistema.
- Ação no menu que não seja um comando registrado ou uma escolha da própria lista (ADR 0005).

## Como eu quero
- `MenuEntry.swift`: uma linha (título, ícone, atalho, ativa ou não, a ação) ou separador;
  `tidy` tira separadores sobrando; MenuStyle.current são as cores, que o app troca junto com o
  tema.
- `PopupMenu.swift`: `PopupMenu.show(_:at:in:)`, `show(_:below:)` (menu de botão) e `show(_:above:)`
  (barra de status, embaixo da janela); `MenuLayout`
  são as medidas e as setas, separadas do desenho para os testes.
- `PopupMenuPanel.swift`: a janela do menu (pega o teclado: setas, Return, Esc; fecha ao perder o
  foco, que é o clique fora) e a lista desenhada à mão. A ação roda depois de fechar, com o
  teclado já de volta na janela de onde o menu abriu.
- `HoverTip.swift`: o nome de um botão de ícone, embaixo dele 0,2 s depois de o ponteiro chegar (o
  do sistema levava cerca de 1 s e tinha outra cara; o dono, 2026-10-20), nas cores dos menus. Some
  ao sair, no clique, numa tecla ou na rolagem. Uma linha tem 22 pt, como sempre; texto maior quebra
  em até 360 pt e cresce para baixo (os commits do histórico na barra lateral, 2026-10-21).
  `HoverTip.attach(_:to:)` troca o toolTip do sistema;
  o toolTip fica só para textos longos de linhas (caminhos, datas).
- `HoverCard.swift`: o cartão sobre um item da barra de status (uso das contas, hosts SSH, portas),
  como popover (seta embaixo apontando o meio do item, a ponta encostada nele). Entra suave 0,18 s
  depois de o ponteiro parar no item (sobe 4 pt aparecendo, 0,15 s), ou na hora no clique; fica
  enquanto o ponteiro está no item, no cartão ou na faixa entre eles, e sai no instante em que não
  está em nenhum (some em 0,1 s). Aberto, olha o ponteiro 30 vezes por segundo; fechado, não custa
  nada. A primeira versão esperava avisos de saída com atrasos encadeados: piscava ao entrar e ficava
  quase 1 s ao sair (o dono, 2026-10-21). `refresh` troca o conteúdo no lugar, sem reabrir. Nas cores
  dos menus, nunca pega o teclado. `HoverRow`, a linha clicável dele, com fundo ao passar.
- `MenuTableView.swift`: tabela cujo clique direito abre o PopupMenu; `menuRow` é a linha clicada
  enquanto o menu está aberto e a ação roda (source control e histórico do git).
- Fontes e medidas de MenuLayout e da dica vêm de UILooks (`../looks/CLAUDE.md`).

## Como validar
- `make macos-test` passa: separadores, setas, medidas, atalhos e a posição da dica.

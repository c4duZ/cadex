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
- `MenuTableView.swift`: tabela cujo clique direito abre o PopupMenu; `menuRow` é a linha clicada
  enquanto o menu está aberto e a ação roda (source control e histórico do git).

## Como validar
- `make macos-test` passa: separadores, setas, medidas e atalhos.

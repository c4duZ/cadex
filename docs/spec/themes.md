# themes

## Para que serve
Dar ao Cadex a cara que o usuário quer: as cores da interface e do terminal, claro ou escuro, e os
temas que ele já usava no Terax.

## Comportamento
- Um tema define as cores da interface (moldura da janela, painéis, abas, campos, texto, destaque)
  e as do terminal (fundo, texto, cursor, seleção e as 16 cores ANSI).
- Cada tema tem versão escura e/ou clara. O usuário escolhe o tema e o modo: seguir o sistema
  (padrão), sempre escuro ou sempre claro. Tema sem a versão pedida mostra a que tem.
- Vêm centenas de temas embutidos (plano 15, `docs/adr/0017-base16-themes.md`):
  - as paletas oficiais de temas abertos, com as variantes (Catppuccin, Rosé Pine, Tokyo Night,
    Kanagawa, Gruvbox, Everforest, GitHub, Ayu, One, Nightfox, Night Owl, Nord, Dracula,
    Solarized), com as cores de terminal dos próprios projetos;
  - os temas do tweakcn, sem os quase iguais, com cores de terminal tiradas das cores de cada um;
  - os esquemas base16 e base24 do tinted-theming.

  O padrão é o Caffeine. Todo tema tem o texto legível: o contraste é conferido ao gerar o
  catálogo. Créditos e licenças estão no `NOTICE`.
- A página de temas acha um tema pela busca (nome ou descrição) e filtra os que têm versão escura
  ou clara. O ⌘K também escolhe o tema (theme.choose) e o modo (theme.mode-system, -dark, -light).
- Seus temas: um arquivo de tema do Cadex por tema na pasta de temas (Application Support/Cadex/themes
  no Mac, %APPDATA%\Cadex\themes no Windows), que aparecem primeiro na lista. Importar (theme.import)
  lê um tema do iTerm2 (.itermcolors), do Ghostty, base16 ou base24 (.yaml) ou do Cadex (.json) e o
  salva nessa pasta. As cores da interface de um tema só de terminal saem do fundo, do texto e do
  azul dele. theme.open-folder abre a pasta.
- O app guarda na memória só o tema em uso; a lista inteira é lida quando a página de temas ou o ⌘K
  a mostram.
- Trocar de tema (ou o sistema mudar de modo) vale na hora em todas as janelas, terminais
  incluídos, sem reabrir nada.
- Programas que perguntam as cores do terminal (OSC 10, 11 e 4, como o vim faz para saber se o
  fundo é escuro) recebem as cores do tema.
- O formato do tema é um arquivo JSON do Cadex (as cores da interface e do terminal). Importar
  temas do Terax ficou de fora: os temas do Terax são os mesmos que vêm embutidos, e o dono não usa
  temas próprios (2026-10-19).
- A janela de configurações também segue o tema. Os menus que abrem pelo clique (clique direito, o
  "+" das abas, as pastas da barra de status) também: as cores do ⌘K, não o menu translúcido do
  sistema (o dono, 2026-10-20). Só a barra de menus do macOS fica do sistema.
- Botões de ícone mostram o nome ao passar o ponteiro, em 0,2 s, embaixo do botão e nas mesmas
  cores dos menus (o dono, 2026-10-20).
- Imagem de fundo: opcional, atrás da área do terminal, com opacidade e desfoque; a imagem escolhida
  é copiada para o Cadex. Vibrância: a moldura fica fosca sobre o que está atrás da janela, e os
  painéis continuam sólidos. As duas vêm desligadas, porque custam desempenho a cada quadro.

## Estados
- **Tema do usuário com erro** (cor inválida, campo faltando): não é carregado; a mensagem diz o
  arquivo, o campo e o valor recusado. O tema em uso continua.
- **Imagem de fundo que sumiu do disco:** o fundo volta a ser a cor do tema.

## Casos de borda
- Cor em `#RGB`, `#RRGGBB` ou `#RRGGBBAA`: aceitas. Qualquer outra forma é recusada.
- Tema com menos de 16 cores ANSI: recusado.

## Critérios de aceite
- [x] Um tema JSON válido é lido; uma cor inválida é recusada com mensagem que cita o campo.
- [ ] O terminal usa o fundo, o texto e as 16 cores do tema (`ls --color` e `vim` mostram as cores).
- [ ] Com "seguir o sistema", trocar o modo do macOS troca o tema na hora.
- [x] Todo tema embutido tem texto do terminal com contraste de 4:1 ou mais, e o da interface com 4,5:1.
- [x] Os temas do tweakcn têm cores de terminal próprias, diferentes entre si.
- [x] Um tema do Ghostty, do iTerm2 e base16 é importado; um arquivo quebrado na pasta aparece com o motivo.
- [ ] A página de temas acha um tema pela busca e filtra claro/escuro, sem criar um cartão por tema.

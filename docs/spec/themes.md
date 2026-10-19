# themes

## Para que serve
Dar ao Cadex a cara que o usuário quer: as cores da interface e do terminal, claro ou escuro, e os
temas que ele já usava no Terax.

## Comportamento
- Um tema define as cores da interface (moldura da janela, painéis, abas, campos, texto, destaque)
  e as do terminal (fundo, texto, cursor, seleção e as 16 cores ANSI).
- Cada tema tem versão escura e/ou clara. O usuário escolhe o tema e o modo: seguir o sistema
  (padrão), sempre escuro ou sempre claro. Tema sem a versão pedida mostra a que tem.
- Vêm 46 temas embutidos: as paletas oficiais de temas abertos (Kanagawa, Kanagawa Dragon, Tokyo
  Night, Catppuccin, Rosé Pine, Everforest, Nord, Gruvbox, Dracula, Solarized), com as cores de
  terminal dos próprios projetos, e os temas do tweakcn, sem os quase iguais. O padrão é o
  Caffeine. Créditos e licenças no `NOTICE`.
- Trocar de tema (ou o sistema mudar de modo) vale na hora em todas as janelas, terminais
  incluídos, sem reabrir nada.
- Programas que perguntam as cores do terminal (OSC 10, 11 e 4, como o vim faz para saber se o
  fundo é escuro) recebem as cores do tema.
- Temas do usuário são arquivos JSON do Cadex numa pasta de temas em Application Support/Cadex.
  Importar um tema do Terax converte o arquivo dele para esse formato, com as mesmas cores.
- Imagem de fundo: opcional, com opacidade e desfoque. Desligada por padrão, porque custa
  desempenho a cada quadro.

## Estados
- **Tema do usuário com erro** (cor inválida, campo faltando): não é carregado; a mensagem diz o
  arquivo, o campo e o valor recusado. O tema em uso continua.
- **Imagem de fundo que sumiu do disco:** o fundo volta a ser a cor do tema.

## Casos de borda
- Cor em `#RGB`, `#RRGGBB` ou `#RRGGBBAA`: aceitas. Qualquer outra forma é recusada.
- Tema com menos de 16 cores ANSI: recusado.
- Arquivo do Terax num formato que o importador não conhece: recusado com mensagem, nada é criado.

## Critérios de aceite
- [x] Um tema JSON válido é lido; uma cor inválida é recusada com mensagem que cita o campo.
- [ ] O terminal usa o fundo, o texto e as 16 cores do tema (`ls --color` e `vim` mostram as cores).
- [ ] Com "seguir o sistema", trocar o modo do macOS troca o tema na hora.
- [ ] Um tema exportado do Terax importado no Cadex tem as mesmas cores.

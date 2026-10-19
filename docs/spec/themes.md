# themes

## Para que serve
Dar ao Cadex a cara que o usuário quer: as cores da interface e do terminal, claro ou escuro, e os
temas que ele já usava no Terax.

## Comportamento
- Um tema define as cores da interface (moldura da janela, painéis, abas, campos, texto, destaque)
  e as do terminal (fundo, texto, cursor, seleção e as 16 cores ANSI).
- Vêm dois temas embutidos: **Cadex Escuro**, no estilo do Terax (moldura cinza-grafite, painéis
  quase pretos, cantos arredondados), e **Cadex Claro**.
- Por padrão o Cadex segue o modo do sistema: escuro no modo escuro, claro no claro. O usuário pode
  fixar um tema nas configurações.
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
- [ ] Um tema JSON válido é lido; uma cor inválida é recusada com mensagem que cita o campo.
- [ ] O terminal usa o fundo, o texto e as 16 cores do tema (`ls --color` e `vim` mostram as cores).
- [ ] Com "seguir o sistema", trocar o modo do macOS troca o tema na hora.
- [ ] Um tema exportado do Terax importado no Cadex tem as mesmas cores.

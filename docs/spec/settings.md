# settings

## Para que serve
Ajustar o Cadex num lugar só: a janela de configurações (⌘,) e o arquivo que guarda as escolhas.

## Comportamento
- ⌘, (ou o comando "Abrir configurações") abre a janela de configurações. Uma só, mesmo chamada
  de novo.
- Páginas, em abas no topo, cada uma com seções; cada opção diz o que muda (refeitas em
  2026-10-20: as explicações estavam mal montadas e o shell estava em Geral):
  - **General / Geral:** Idioma (`general.language`, "en" padrão ou "pt"; vale ao reabrir, e a
    troca oferece "Reabrir agora", com as abas e os spaces de volta; ver
    `../adr/0015-english-default-two-languages.md`). Arquivos: onde abrem, ao lado do painel com
    foco (padrão) ou em nova aba (`general.openFiles`), de que lado fica o arquivo aberto ao lado,
    com metade da aba (`tabs.documentSide`, direita por padrão), e como uma nota Markdown abre
    (`markdown.openAs`), e para onde vai o elemento escolhido no preview, o terminal do agente
    (padrão) ou a área de transferência (`preview.pickTarget`, ver `preview.md`), com print do
    elemento ou não (`preview.pickScreenshot`, ligado). Árvore de arquivos: seguir o terminal (`explorer.followTerminal`) e
    mostrar os ocultos (`explorer.showHidden`). Manter acordado: como liga e desliga, o modo
    (`power.mode`), manter a tela acesa, ligar ao abrir (`power.onAtLaunch`) e a tampa fechada
    explicada à parte (ver `power.md`). Numa página própria ficou demais (o dono, 2026-10-20).
  - **Terminal:** Shell (o programa, vazio usa o do usuário; perguntar antes de fechar um programa
    rodando; perguntar antes de colar várias linhas). Texto e cursor (fonte, tamanho, cursor,
    piscando). Histórico e teclado (linhas, Option esquerdo como Meta, copiar ao selecionar).
  - **Themes / Temas:** modo claro ou escuro, o tema, a vibrância e a imagem de fundo.
  - **Shortcuts / Atalhos:** a lista de comandos com o atalho de cada um, editável, com aviso de
    conflito.
  - **About / Sobre:** versão e créditos.
- Toda mudança vale na hora, em todas as janelas, sem botão de salvar.
- As escolhas ficam num arquivo só, `settings.json` em Application Support/Cadex, que o usuário
  também pode editar à mão. Os atalhos personalizados moram nele, na seção `shortcuts`.
- Editar o arquivo com o Cadex aberto também vale na hora.

- Plano 15: Temas ganha escuro e claro, cor de destaque, alto contraste e painéis sem foco;
  Terminal ganha a seção Leitura (contraste mínimo, altura de linha, espaçamento, ligaduras,
  recursos da fonte); Geral ganha Interface (zoom, densidade, fonte e tamanho da interface:
  appearance.uiZoom, appearance.density, appearance.uiFont, appearance.uiFontSize), que valem ao
  reabrir o Cadex, como o idioma. settings.open-themes e settings.open-terminal abrem essas páginas
  pelo ⌘K.

## Estados
- **Sem arquivo:** valem os padrões; o arquivo nasce na primeira mudança.
- **Arquivo com erro:** valem os padrões para o que estiver errado; o aviso vai para o log e o resto
  do arquivo continua valendo.

## Casos de borda
- Tamanho de fonte fora de 8 a 32 pt: ajustado para o limite mais próximo.
- Histórico acima de 100 mil linhas: limitado a 100 mil (memória).
- Fonte que não existe no sistema: volta para SF Mono, com aviso no log.

## Critérios de aceite
- [x] Preferências salvas e relidas dão os mesmos valores.
- [x] Mudar o tamanho da fonte redesenha os terminais abertos com as novas métricas.
- [x] Um `settings.json` editado à mão com o app aberto vale na hora.
- [x] Um `settings.json` quebrado não impede o app de abrir.
- [x] Sem `general.openFiles` no arquivo, arquivos abrem ao lado; "tab" abre em nova aba.

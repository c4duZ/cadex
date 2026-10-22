# tabs

## Para que serve
Ter vários terminais e arquivos abertos na mesma janela: abas lado a lado na barra, cada aba
dividida em painéis. Um painel mostra um terminal ou um documento (código, Markdown, mídia, preview
web, diff, histórico do git), e um documento tem um ponto no título quando há mudança não salva.

## Comportamento

### Abas
- ⌘T abre uma aba de terminal na pasta da sessão ativa; sem sessão ativa, na pasta pessoal. A aba
  nova entra à direita da atual e ganha o foco.
- O título da aba é o nome da pasta atual da sessão com foco (a pasta pessoal aparece como `~`).
  Muda quando a pasta muda.
- Renomear (comando "Renomear aba", ou duplo clique no título) dá um nome que fica mesmo mudando de
  pasta. Renomear para vazio volta ao nome da pasta.
- ⌘1 a ⌘9 vão para a aba daquela posição. Ctrl+Tab e Ctrl+⇧+Tab alternam pela ordem de uso
  (Ctrl+Tab volta para a aba usada antes da atual).
- Arrastar uma aba na barra muda a posição dela.
- Clicar numa aba vai para ela; o × da aba ou o clique do meio (botão 3 do mouse) fecha a aba.
- Com o ponteiro sobre uma aba, em 0,2 s aparece a pasta do terminal (~ no lugar da pasta pessoal)
  ou o caminho do arquivo; sobre o ×, "Fechar aba" (o dono, 2026-10-20).
- As abas são o elemento principal da barra de cima: largura igual (até 220 pt, encolhendo quando
  não cabem), cada uma com fundo próprio, a ativa com fundo mais forte e uma linha na cor do tema
  embaixo; ícone do que mostram (terminal, arquivo pelo tipo, histórico, página web). O × aparece
  na ativa e na que está sob o ponteiro. O dono escolheu esse estilo, o das abas nativas do macOS,
  no lugar de pílulas discretas (2026-10-19).
- A barra de abas aparece mesmo com uma aba só (o visual final vem com a feature themes).

### Divisões
- ⌘D divide o painel com foco para a direita; ⌘⇧D, para baixo. O painel novo abre na mesma pasta e
  ganha o foco. Painéis numa mesma direção ficam do mesmo tamanho: três lado a lado têm um terço
  cada, e fechar um devolve o espaço aos outros por igual (antes ficavam 50, 25 e 25 %).
- Arrastar a linha entre dois painéis muda o tamanho; nenhum painel fica menor que algumas colunas.
  A linha pega o mouse a 6 pt de cada lado, com o cursor de redimensionar, e engrossa sob o
  ponteiro e enquanto arrasta.
- ⌘] e ⌘[ passam o foco para o próximo e o anterior painel da aba, em volta. ⌘⌥ + seta passa para
  o painel vizinho naquela direção.
- Clicar num painel dá o foco a ele. Os painéis sem foco ficam levemente escurecidos (sem contorno
  azul, que o dono achou tosco); eles continuam recebendo saída e atualizando.

### Documentos em painéis
- Todo painel guarda um terminal ou um documento e funciona igual nos dois casos: dividir (⌘D,
  ⌘⇧D), passar o foco (⌘], ⌘[, ⌘⌥ + seta, clique), fechar (⌘W, ×), arrastar o divisor, tamanhos
  iguais, escurecer quando sem foco, salvar e restaurar nos spaces. Uma aba de documento é uma aba
  com um painel só.
- A configuração "Abrir arquivos" (Geral; `general.openFiles`) decide onde arquivos, mídia, diff,
  histórico e preview web abrem: **Ao lado** (padrão) ou **Em nova aba**. "Abrir ao lado" e "Abrir
  em nova aba" (explorer e paleta) escolhem na hora, sem mudar a configuração.
- "Ao lado", nesta ordem: (1) o documento já está num painel de alguma aba → vai para ele (aba e
  foco); (2) a aba ativa já tem um painel de documento sem mudança não salva → o novo toma o lugar
  dele (o antigo fecha); (3) senão, o documento entra encostado num lado da aba, com metade dela e o
  foco, e os painéis que já existiam ficam na outra metade, do jeito que estavam (issue #5, o dono,
  2026-10-21); o lado é a configuração "Lado do arquivo aberto ao lado" (`tabs.documentSide`,
  direita por padrão, ou esquerda); (4) com um documento já encostado e não salvo, o painel com
  foco divide para a direita; (5) sem espaço → nova aba. Abrir vários arquivos ao lado não empilha
  divisões.
- O documento encostado guarda a metade dele: dividir ou fechar terminais reparte só a outra
  metade, e arrastar o divisor entre os dois lados mantém a proporção escolhida. Fechar o documento
  devolve a aba inteira aos painéis, no arranjo de antes. Um documento num lado da divisão de fora
  da aba é tratado como encostado, inclusive numa aba restaurada pelos spaces.
- "Em nova aba": o documento abre numa aba própria à direita da ativa, ou vai para a aba/painel
  que já o mostra.
- ⌘D e ⌘⇧D com o foco num documento abrem um terminal ao lado, na pasta do arquivo.
- Título e ícone da aba vêm do painel com foco (terminal: pasta ou programa; documento: título e
  ícone do tipo). "●" no título quando qualquer painel da aba tem mudança não salva.

### Cabeçalho dos painéis
- Com 2 ou mais painéis numa aba, cada um ganha em cima uma linha fina (24 pt, sem fundo, um fio
  embaixo): à esquerda o ícone e o nome (o arquivo, com ● se não salvo; o programa do terminal, ou a
  pasta); à direita + (terminal ao lado, terminal abaixo, preview web ao lado, maximizar, fechar o
  painel, cada um com ícone e atalho), maximizar e ✕. Os três aparecem juntos, sempre no painel com
  foco e ao passar o ponteiro nos outros, e guardam o lugar quando somem, para o cabeçalho não mexer
  (o maximizar aparecendo sozinho mexia, 2026-10-22). O botão do meio do mouse fecha o painel, como
  fecha uma aba; o painel com foco tem
  uma linha da cor de destaque em cima e o nome mais forte. Mais leve que as abas da janela, para não
  parecer uma segunda fileira de abas. Resolve o issue #1: o arquivo aberto ao lado tinha só o ⌘W.
- Arrastar o cabeçalho move o painel (a ideia do dono, 2026-10-22): a aba vira um quadro em que cada
  painel é uma janela cinza só com o cabeçalho (ícone e nome), e as janelas se reorganizam ao vivo,
  com uma animação de 0,3 s que passa um pouco do ponto, mostrando como vai ficar; a do painel
  arrastado fica esmaecida, no mesmo cinza, sem contorno colorido (o dono, 2026-10-22), e uma etiqueta com o nome segue o ponteiro. Os painéis
  de verdade ficam parados atrás e só mudam ao soltar (o terminal recebe o tamanho novo uma vez).
- Onde cai é medido no layout do começo do arraste, não nas janelas que se mexem (medir nelas fazia o
  destino escorregar e o layout tremer): sobre outro painel, os lados pelas diagonais (esquerda,
  direita, cima, baixo, dividindo o espaço dele); o centro (40%) e o cabeçalho dele trocam os dois de
  lugar (arrastar para a direita pela linha dos cabeçalhos troca, em vez de dividir); um lado que não
  mudaria nada também troca. Só muda de área depois de o ponteiro andar 8 pt. Sobre o próprio painel
  ou fora, nada; Esc cancela. Como o Zed, o yabai e o VS Code decidem (pesquisa de 2026-10-22).
- Clique no cabeçalho dá o foco ao painel; duplo clique maximiza. Cada botão roda um comando
  (pane.close, pane.zoom, pane.split-right, pane.split-down).
- Maximizar (pane.zoom, ⇧⌘↩): o painel ocupa a aba toda, os outros saem de vista e voltam ao
  restaurar; dar o foco a outro painel também restaura.
- Com um painel só, nada muda: sem cabeçalho. tabs.paneHeaders: "split" (padrão), "always" ou
  "never" (Configurações › Temas, ao lado de "Painéis sem foco"), como a opção do iTerm2.
- Escolhido depois de pesquisa (2026-10-22): editores dão abas a cada painel (VS Code, Zed); os
  terminais, nenhum cabeçalho ou um só com divisões (iTerm2). Abas por painel trariam um segundo
  nível de aba atual e o caso do grupo vazio; o cabeçalho fino basta para fechar o certo.

### Fechar
- ⌘W fecha o painel com foco. O espaço dele vai para o vizinho. Se era o único da aba, fecha a aba.
  Se era a última aba, fecha a janela.
- Quando o shell de um painel termina (`exit`, Ctrl+D), o painel fecha da mesma forma.
- Fechar painel, aba ou janela com um programa em primeiro plano (servidor, agente, `sleep 100`)
  pede confirmação, com "não perguntar de novo". Com o shell parado, fecha direto.
- Fechar um painel de documento com mudança não salva pergunta ao documento (salvar, descartar,
  cancelar). Fechar aba ou janela soma os arquivos não salvos de todos os painéis numa pergunta só.

### Desempenho
- Abas que não estão visíveis não desenham; continuam lendo a saída do shell.

- O escurecimento dos painéis sem foco é ajustável (tabs.unfocusedDim, de 0 a 0,6; 0,26 por
  padrão; 0 desliga).
- Clique direito numa aba: renomear, cor da aba e fechar painel, pelos comandos (plano 15, fase D).

## Estados
- **Uma aba, um painel:** como o terminal sozinho, com a barra de abas em cima.
- **Shell não abre** (shell configurado não existe): a aba abre mostrando o erro (spec do terminal).

## Casos de borda
- ⌘5 com três abas: nada acontece.
- Dividir um painel muito pequeno: recusa se as metades ficariam abaixo do mínimo.
- Fechar o painel do meio de três: o espaço vai para o vizinho da mesma divisão.
- Pasta da sessão sumiu (apagada): a aba nova abre na pasta pessoal.
- Abrir ao lado com o painel de documento da aba não salvo: divide em vez de trocar (nada se perde).
- Abrir ao lado num painel pequeno demais para dividir: abre em nova aba.

## Critérios de aceite
- [x] ⌘T abre na pasta atual depois de um `cd` na aba ativa.
- [x] Renomear mantém o nome depois de um `cd`; renomear para vazio volta ao nome da pasta.
- [x] ⌘1 a ⌘9 trocam de aba; Ctrl+Tab volta para a aba usada antes.
- [x] ⌘D e ⌘⇧D dividem e o painel novo abre na mesma pasta.
- [x] ⌘W com `sleep 100` no painel pede confirmação; com o shell parado, fecha direto.
- [x] Fechar o último painel da última aba fecha a janela.
- [x] Árvore de painéis: dividir, fechar e reequilibrar dão o layout esperado.
- [x] Abas escondidas não desenham.
- [x] Abrir ao lado segue as quatro regras: painel existente, troca, divisão, nova aba.
- [x] Abrir ao lado com o documento da aba não salvo divide em vez de trocar.
- [x] Com terminais divididos, o arquivo aberto ao lado fica com metade da aba; dividir um terminal
  não tira espaço dele; fechá-lo devolve a aba aos terminais; com `tabs.documentSide` "left", ele
  encosta à esquerda.
- [x] Clicar num documento dá o foco a ele; ⌘], ⌘[ e ⌘⌥ + seta passam por documentos.
- [x] ⌘D num documento abre um terminal ao lado, na pasta do arquivo.
- [x] Fechar painel, aba ou janela com documento não salvo pergunta antes.

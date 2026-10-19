# tabs

## Para que serve
Ter vários terminais e arquivos abertos na mesma janela: abas lado a lado na barra; abas de
terminal se dividem em painéis. Abas de documento (editor; mídia e preview com as features delas)
mostram um arquivo e têm um ponto no título quando há mudança não salva.

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
- As abas são o elemento principal da barra de cima: largura igual (até 220 pt, encolhendo quando
  não cabem), cada uma com fundo próprio, a ativa com fundo mais forte e uma linha na cor do tema
  embaixo; ícone do que mostram (terminal, arquivo pelo tipo, histórico, página web). O × aparece
  na ativa e na que está sob o ponteiro. O dono escolheu esse estilo, o das abas nativas do macOS,
  no lugar das pílulas discretas do Terax (2026-10-19).
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

### Fechar
- ⌘W fecha o painel com foco. O espaço dele vai para o vizinho. Se era o único da aba, fecha a aba.
  Se era a última aba, fecha a janela.
- Quando o shell de um painel termina (`exit`, Ctrl+D), o painel fecha da mesma forma.
- Fechar painel, aba ou janela com um programa em primeiro plano (servidor, agente, `sleep 100`)
  pede confirmação, com "não perguntar de novo". Com o shell parado, fecha direto.

### Desempenho
- Abas que não estão visíveis não desenham; continuam lendo a saída do shell.

## Estados
- **Uma aba, um painel:** como o terminal sozinho, com a barra de abas em cima.
- **Shell não abre** (shell configurado não existe): a aba abre mostrando o erro (spec do terminal).

## Casos de borda
- ⌘5 com três abas: nada acontece.
- Dividir um painel muito pequeno: recusa se as metades ficariam abaixo do mínimo.
- Fechar o painel do meio de três: o espaço vai para o vizinho da mesma divisão.
- Pasta da sessão sumiu (apagada): a aba nova abre na pasta pessoal.

## Critérios de aceite
- [x] ⌘T abre na pasta atual depois de um `cd` na aba ativa.
- [x] Renomear mantém o nome depois de um `cd`; renomear para vazio volta ao nome da pasta.
- [x] ⌘1 a ⌘9 trocam de aba; Ctrl+Tab volta para a aba usada antes.
- [x] ⌘D e ⌘⇧D dividem e o painel novo abre na mesma pasta.
- [x] ⌘W com `sleep 100` no painel pede confirmação; com o shell parado, fecha direto.
- [x] Fechar o último painel da última aba fecha a janela.
- [x] Árvore de painéis: dividir, fechar e reequilibrar dão o layout esperado.
- [x] Abas escondidas não desenham.

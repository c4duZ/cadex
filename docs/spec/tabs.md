# tabs

## Para que serve
Ter vários terminais abertos na mesma janela: abas lado a lado na barra, e cada aba dividida em
painéis. Hoje só abas de terminal; editor, preview e outras entram com as features delas.

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
- Clicar numa aba vai para ela; o × da aba fecha a aba.
- A barra de abas aparece mesmo com uma aba só (o visual final vem com a feature themes).

### Divisões
- ⌘D divide o painel com foco para a direita; ⌘⇧D, para baixo. O painel novo abre na mesma pasta e
  ganha o foco; o espaço é dividido ao meio.
- Arrastar a linha entre dois painéis muda o tamanho; nenhum painel fica menor que algumas colunas.
- ⌘] e ⌘[ passam o foco para o próximo e o anterior painel da aba, em volta. ⌘⌥ + seta passa para
  o painel vizinho naquela direção.
- Clicar num painel dá o foco a ele. O painel com foco tem um destaque discreto; os outros continuam
  recebendo saída e atualizando.

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

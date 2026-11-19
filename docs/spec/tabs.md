# tabs

## Para que serve
Ter vários terminais e arquivos abertos na mesma janela: abas lado a lado na barra de cima, cada
aba dividida em painéis. Um painel mostra um terminal ou um documento (código, Markdown, mídia,
preview web, diff, histórico do git), e um documento tem um ponto no título quando há mudança não
salva. Cara e medidas da moldura nova (`../adr/0035-work-frame.md`; `../design/work-frame/screens.md`,
seções TitleBar, Terminals e Pane; tokens components.tab e components.pane em
`../design/work-frame/tokens.json`).

## Comportamento

### Abas
- A barra de cima, da esquerda para a direita (`../adr/0039-sidebar-with-work-and-files.md`, plano
  38): o botão da barra lateral (⌘B, aceso com ela aberta); **o lugar**, o avatar e "projeto ›
  tarefa ▾" (no main, só o projeto), cujo clique abre o menu do lugar: o main e as tarefas do
  projeto, a página do projeto, os outros projetos e "Trocar de projeto…" (project.switch, a lista
  com busca no ⌘K); as abas do lugar e o "+"; **Revisar**, só dentro de uma tarefa, um botão com
  contorno depois de um fio (git.review-open); à direita, a pílula "precisa de você" (só com a barra
  lateral fechada e algum pedido aberto; `sidebar.md`) e Buscar ⌘K no fim. A conta, o quadro, o sino
  e a engrenagem não estão na barra de cima (a conta e o café na barra de baixo, o quadro no pé da
  barra lateral, ⌘, e o menu para as configurações).
- As abas são do lugar escolhido na barra lateral (`sidebar.md`): os terminais e documentos do
  projeto fora de tarefa (o main), ou os de uma tarefa (na worktree dela). Os terminais só aparecem
  aqui, nunca listados na barra lateral. As tarefas não são itens da barra de abas: elas estão na
  barra lateral e no menu do lugar; o único item extra é "Compare", nas abas de uma corrida.
- **Quando não cabem:** as abas encolhem juntas até o tamanho mínimo; daí em diante as que sobram vão
  para "» N" no fim, que abre a lista delas para escolher; a ativa fica sempre à mostra.
- **Abas sem projeto:** os terminais da pasta pessoal não viram projeto; enquanto se está neles,
  nenhum lugar da barra lateral fica aceso e a barra de cima fica sem o lugar.
- ⌘T abre uma aba de terminal na pasta da seleção (a da tarefa, ou a do projeto); sem projeto, na
  pasta pessoal. A aba nova entra à direita da atual e ganha o foco. O "+" depois das abas faz o
  mesmo, com o menu do que mais abrir.
- O título da aba é o nome da pasta atual da sessão com foco (a pasta pessoal aparece como `~`).
  Muda quando a pasta muda.
- Renomear (comando "Renomear aba", ou duplo clique no título) dá um nome que fica mesmo mudando de
  pasta. Renomear para vazio volta ao nome da pasta.
- Toda aba que roda algo mostra antes do título a peça de estado do app (components.stateGlyph):
  um agente do Claude Code (plano 19) com os estados dele (trabalhando, precisa de você, pronto,
  falhou, parado), um programa qualquer com o anel enquanto roda; um servidor (uma porta aberta) fica
  sem peça, com o nome do comando e a oferta do preview, porque o verde é só "agente pronto" (plano
  37). "» N" leva o estado mais urgente das abas escondidas, e a lista dele diz o de cada uma. Aba de agente: o nome da conversa no lugar da pasta e, ao passar o ponteiro,
  a frase do que ele faz agora; "pronto sem você ver" deixa o título em negrito até o terminal
  ganhar o foco. O nome dado à mão continua vencendo; o estado aparece mesmo assim.
- Com terminal.keepSessions ligado (plano 19), fechar a janela principal ou o app deixa os shells das
  abas vivos no daemon do terminal, sem perguntar por programa rodando (ele segue rodando), e reabrir
  religa cada aba ao seu; fechar uma aba ou um painel encerra o shell dele, pedindo confirmação com
  programa rodando, como hoje. As janelas do ⇧⌘N (window.new) não salvam projetos: os terminais delas são do app,
  como com a opção desligada.
- ⌘1 a ⌘9 vão para a aba daquela posição. Ctrl+Tab e Ctrl+⇧+Tab alternam pela ordem de uso
  (Ctrl+Tab volta para a aba usada antes da atual).
- Arrastar uma aba na barra muda a posição dela.
- Clicar numa aba vai para ela; o × da aba ou o clique do meio (botão 3 do mouse) fecha a aba.
- Com o ponteiro sobre uma aba, em 0,2 s aparece a pasta do terminal (~ no lugar da pasta pessoal)
  ou o caminho do arquivo; sobre o ×, "Fechar aba" (o dono, 2026-10-20).
- Cara das abas (components.tab): 30 pt de altura, raio 7, 12 pt de lado, largura do título; a
  ativa com o fundo de etiqueta e o texto forte, as outras sem fundo e com o texto secundário; sem
  linha embaixo. Ícone do que mostram (a peça de estado no que roda algo; arquivo pelo tipo,
  histórico, página web). O × aparece na aba sob o ponteiro, por cima do fim do título (o mockup não mostra × na
  ativa). Revê o estilo de abas
  nativas com fundo e linha na cor do tema (o dono, 2026-10-19), pelo mockup aprovado em 2026-11-17.
- A barra de abas aparece mesmo com uma aba só.

- Arrastar uma aba pela barra muda a ordem: ela vai por cima seguindo o ponteiro e as outras deslizam
  para a vaga nova enquanto ela passa (0,15 s); cai onde o meio dela
  está. Nada clicável da barra de cima (abas e botões) arrasta a janela: ela fica travada enquanto o
  ponteiro está neles e solta ao sair; a parte vazia da barra continua movendo a janela. O macOS
  decide mover a janela antes de o app ver o clique, então travar só no clique não bastava (o dono,
  2026-10-22).

### Divisões
- ⌘D divide o painel com foco para a direita; ⌘⇧D, para baixo. O painel novo abre na mesma pasta e
  ganha o foco. Painéis numa mesma direção ficam do mesmo tamanho: três lado a lado têm um terço
  cada, e fechar um devolve o espaço aos outros por igual (antes ficavam 50, 25 e 25 %).
- Arrastar a linha entre dois painéis muda o tamanho; nenhum painel fica menor que algumas colunas.
  A linha pega o mouse a 8 pt de cada lado, numa faixa por cima do terminal e dos cabeçalhos, com o
  cursor de redimensionar firme em toda ela (por baixo, o terminal trocava o cursor e ele ia e voltava,
  2026-10-22), e engrossa sob o
  ponteiro e enquanto arrasta.
- ⌘] e ⌘[ passam o foco para o próximo e o anterior painel da aba, em volta. ⌘⌥ + seta passa para
  o painel vizinho naquela direção.
- Clicar num painel dá o foco a ele. Os painéis são arredondados (raio 10), com 8 pt entre eles e
  em volta. O com foco tem o contorno discreto e um halo azul a 10% (components.pane.focused); os
  sem foco, o fundo e o contorno mais apagados e 92% de opacidade (components.pane.idle), e
  continuam recebendo saída e atualizando. Revê "sem contorno azul, que o dono achou tosco" e "os
  painéis continuam colados" (2026-10-22), pelo mockup aprovado em 2026-11-17: o contorno agora é
  da cor das linhas, não azul, e só o halo é azulado.

### Documentos em painéis
- Todo painel guarda um terminal ou um documento e funciona igual nos dois casos: dividir (⌘D,
  ⌘⇧D), passar o foco (⌘], ⌘[, ⌘⌥ + seta, clique), fechar (⌘W, ×), arrastar o divisor, tamanhos
  iguais, escurecer quando sem foco, salvar e restaurar nos projetos. Uma aba de documento é uma aba
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
  da aba é tratado como encostado, inclusive numa aba restaurada pelos projetos.
- "Em nova aba": o documento abre numa aba própria à direita da ativa, ou vai para a aba/painel
  que já o mostra.
- ⌘D e ⌘⇧D com o foco num documento abrem um terminal ao lado, na pasta do arquivo.
- Título e ícone da aba vêm do painel com foco (terminal: pasta ou programa; documento: título e
  ícone do tipo). "●" no título quando qualquer painel da aba tem mudança não salva.

### Cabeçalho dos painéis
- Todo painel tem cabeçalho, com um ou com vários (components.pane.header: 34 pt, um fio embaixo):
  à esquerda a peça de estado, o nome (o arquivo, com ● se não salvo; o programa do terminal; o
  agente) e, mais apagado, de onde é (a tarefa, o modelo, a conta); à direita o que interessa ao
  painel (o custo e o tempo de um agente; "running 38 s" de um comando; a etiqueta azul "Open :5173
  in preview" de um servidor). Ao passar o ponteiro aparecem também + (terminal ao lado, terminal
  abaixo, preview web ao lado, maximizar, fechar o painel, cada um com ícone e atalho), maximizar e
  ✕; parados não aparecem, como no mockup, e o custo fica na borda direita. O botão do meio do mouse fecha o painel, como fecha uma aba.
  O cabeçalho só se redesenha quando o que ele mostra muda (custo e tempo no máximo uma vez por
  segundo), nunca a cada tecla.
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
- tabs.paneHeaders saiu no plano 28: o cabeçalho é sempre (o mockup mostra um painel só com
  cabeçalho); um arquivo antigo com a chave abre sem aviso.
- Cada painel é uma caixa (components.pane): cantos de 10 pt, 8 pt em volta e entre as caixas, sem
  linha divisória (arrastar o vão redimensiona; sob o ponteiro, uma barra curta no meio dele); a com
  foco no fundo da moldura com a linha de foco e um anel de 3 pt; as outras num fundo um tom mais
  escuro e a 92% (components.pane.idle). O terminal tem 14 × 16 pt de respiro dentro da caixa.

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

- Os painéis sem foco ficam a 92% (components.pane.idle.opacity); tabs.unfocusedDim, a sombra
  ajustável de antes, saiu no plano 28.
- Clique direito numa aba: renomear, cor da aba e fechar painel, pelos comandos (plano 15, fase D).

## Estados
- **Uma aba, um painel:** o painel com o cabeçalho dele, a barra de abas em cima.
- **Shell não abre** (shell configurado não existe): a aba abre mostrando o erro (spec do terminal).

## Casos de borda
- ⌘5 com três abas: nada acontece.
- Dividir um painel muito pequeno: recusa se as metades ficariam abaixo do mínimo.
- Fechar o painel do meio de três: o espaço vai para o vizinho da mesma divisão.
- Pasta da sessão sumiu (apagada): a aba nova abre na pasta pessoal.
- Abrir ao lado com o painel de documento da aba não salvo: divide em vez de trocar (nada se perde).
- Abrir ao lado num painel pequeno demais para dividir: abre em nova aba.

### Abas da tarefa (plano 29; plano 38)
- A barra de cima mostra as abas de onde você está: numa tarefa, as dela (os terminais e documentos
  na worktree dela), com o botão Revisar depois delas; no main, as do projeto. ⌘1…⌘9 e arrastar
  contam as mostradas. Ir de uma para a outra é pela barra lateral ou pelo menu do lugar
  (project.show-terminals volta às do projeto).
- Uma aba com vários terminais se chama "Terminals · N", com o estado mais importante deles; um
  terminal rodando um comando leva o nome do comando (`terminal.md`).

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
- [ ] Cada aba e cada cabeçalho de painel com algo rodando mostra a peça de estado certa.
- [x] Escolher uma tarefa na barra lateral põe as abas dela em cima, e o main volta às do projeto
      (conferido no app, plano 38 B).
- [ ] O menu do lugar e o Revisar numa tarefa conferidos com o clique de verdade (plano 38 E: o
      clique de teste não chega à barra de cima).
- [ ] "» N" aparece numa janela de verdade com abas demais.
- [ ] Uma aba com o Claude Code mostra o estado e o nome da conversa; o nome dado à mão
      continua; com keepSessions ligado, fechar e reabrir o app religa a aba ao mesmo shell.

## Páginas (plano 31 E; plano 34)
- Uma página nunca aparece na barra de cima: ela mostra as abas de terminal de onde se veio, nenhuma
  acesa, com o "+" e o lugar iguais. Uma página por vez (abrir outra troca); o Esc numa página, ou o
  clique numa aba, volta ao terminal de antes. As seções de uma página ficam dentro dela.
- O que é para ler de corpo inteiro abre como página, na própria aba, nunca dividido ao lado de um
  terminal, qualquer que seja general.openFiles: a revisão (e o diff de um arquivo), o histórico do
  git, a transcrição de uma conversa, o briefing da memória, o arquivo de conversas, o quadro, a
  página do projeto, a da execução e a da automação. Arquivo, Markdown, mídia e preview continuam
  abrindo ao lado, porque se trabalha com eles junto do terminal.

# status-bar

## Para que serve
Mostrar, embaixo da janela, o ambiente que quem usa quer ter sempre à vista: o projeto e o branch,
quantos agentes trabalham, a conta mais perto do limite, onde roda e, se quiser, RAM, CPU, SSH e
outros. Cada pessoa monta a própria barra. Ela não conta pedidos: a casa deles é a fila "Precisa de
você" da barra lateral (`sidebar.md`; `../adr/0039-sidebar-with-work-and-files.md`). Cara e medidas da moldura nova
(`../adr/0035-work-frame.md`; `../design/work-frame/screens.md`, seção StatusBar; tokens em
`../design/work-frame/tokens.json`, components.statusBar).

## Comportamento
### Os itens
A barra tem dois lados, esquerda e direita, e cada lado é uma lista de itens em ordem. Itens:

| item | mostra | padrão |
|---|---|---|
| Project | "cadex · main ↑3": o projeto e o branch, com ↑↓ de commits a enviar/receber | ligado, esquerda |
| Agents | "● 3 working" (azul), só quem trabalha; some com zero; o clique abre o quadro (view.board) | ligado, esquerda |
| Folder | a trilha "Home › Cadu › Trabalho › cadex" do terminal com foco | desligado |
| Terminal | "Terminal ⌥⌘`": mostra ou esconde a gaveta de terminais | ligado, direita |
| Memory | "Memory · 214 pages": abre a memória do projeto (memory.show, a seção Memória da página do projeto) | ligado, direita |
| Agent usage | a conta do agente do terminal com foco, ou a última (a escolha do dono, 2026-10-21): "Claude bkdg 84% · resets 3h", em etiqueta âmbar acima de 80% e texto comum abaixo; passar o ponteiro abre todas as contas (`agents.md`) | ligado, direita |
| Environment | "Local" no macOS (no Windows, a distro WSL), ou a máquina onde roda | ligado, direita |
| Keep awake | o café, sempre à vista como era na barra de cima: cheio ligado, contorno desligado; o clique roda power.toggle (`power.md`) | ligado, direita |
| Update | "Update to 2.6": só com versão nova para instalar; o clique roda app.check-for-updates (`updates.md`) | ligado, direita, só com versão nova |
| RAM | memória do sistema em uso: "12.4 / 16 GB" | desligado |
| CPU | uso do processador do sistema: "CPU 18%" | desligado |
| Cadex memory | a memória do próprio Cadex: "61 MB" | desligado |
| Terminals | terminais abertos: "›_ 4" | desligado |
| Ports | portas ouvindo nos processos dos terminais do Cadex: "⌁ 2 (:3000, :5173)" | desligado |
| SSH | hosts no ar: "SSH 3/3 ●" (`ssh.md`) | desligado |
| Tailscale | as máquinas da tailnet: "Tailnet 2/3" (`machines.md`) | desligado |
| Docker | o contexto do Docker da aba com foco, quando não é o deste Mac | desligado |

Sem mexer em nada, a barra é a do mockup: projeto e agentes à esquerda; Terminal, Memory, a
conta, o café, o ambiente (e a atualização quando há versão nova) à direita. O mockup não desenha
o café: ele entra na barra de status para continuar sempre à vista, como o dono pediu quando ele
estava na barra de cima (`power.md`). A conta e o café só estão aqui: a barra de cima não os tem. Quem tinha a barra
personalizada antes mantém a dele, com Folder e Git branch virando Project quando os dois estavam
ligados.

### Mudanças sem pulo
- Os itens clicáveis (projeto, terminais, agentes, uso, memória, café, atualização, portas, SSH, RAM, CPU, memória do Cadex)
  acendem com um fundo arredondado ao passar o ponteiro, como os botões da barra de cima; cada item
  guarda 6 pt em volta para o fundo, sem mudar o espaço entre os textos (o dono, 2026-10-22).
- Quando um item muda de largura (a pasta, o branch, a conta, ao trocar de aba ou de conta), os que
  estão depois dele deslizam para o lugar novo (0,22 s) em vez de pular, e o texto que muda esmaece
  para o novo (0,18 s). O branch passa de 180 pt e o nome da conta de 150 pt cortados com "…" (inteiros
  na dica), para um nome longo não empurrar a barra inteira.
- O branch nunca passa por "nenhum" ao trocar de pasta: o anterior fica até o novo chegar, e um
  repositório já visto mostra o último branch dele na hora. A pasta de um terminal que falha ao ser
  lida por um instante fica a última conhecida. O item da conta só se redesenha quando a conta muda
  (antes se refazia a cada saída do terminal). O dono via a barra piscar e mudar as coisas de lugar
  (2026-10-22).

### Personalizar
- Botão direito na barra: menu com cada item (marcado se aparece) e "Customize Status Bar…".
- "Customize Status Bar…" abre a janela Customize na aba Status Bar: as seções Left e
  Right com todos os itens, cada um com chave; arrastar uma linha reordena, e passando para a outra
  seção ela muda de lado. Os escondidos ficam embaixo do lado de costume deles.
- No ⌘K: "Customize Status Bar" e "Show or Hide a Status Bar Item" (a lista dos itens, cada um
  marcado como aparece ou escondido).
- Vale para todas as janelas na hora e fica no settings.json (statusBar.left e statusBar.right).
- Item escondido não custa nada: não mede, não vigia, não pergunta à rede.

### Folder
- Clicar num pedaço da trilha abre um menu com as subpastas daquele nível; escolher uma leva o
  terminal com foco até ela (`cd`), só se o shell estiver parado no prompt. Com um programa rodando,
  o menu mostra as pastas apagadas.
- A trilha acompanha o terminal com foco: trocar de aba ou de painel troca a pasta mostrada.

### Medidas
- RAM, CPU e Cadex memory são lidos a cada 2 s, só com o item visível e a janela na tela; com a
  janela escondida ou minimizada, param.
- Ports é lido quando um terminal abre, fecha ou um programa termina, e a cada 10 s enquanto um
  programa roda num terminal.
- Clicar em RAM, CPU ou Cadex memory abre o Monitor de Atividade; em Ports, o cartão com cada porta
  (passar o ponteiro também abre; "localhost:3000" abre no preview); em Agent usage, o popover das
  contas (cada conta com plano, quando zera, a barra e "84% of the 5-hour window · 61% of the
  week", e "Open an agent on… · Add account · Accounts settings"; é o que era a página Accounts);
  em Agents, o quadro; em Project, Mudanças na barra lateral (git.show).

### Os cartões (o dono, 2026-11-18; a proposta aprovada em https://claude.ai/artifact/4nVtRBCgr1PRhhMVRSWmRK)
Todo item abre um cartão ao passar o ponteiro (o comportamento do cartão das contas: 0,18 s depois
de parar, fica enquanto o ponteiro está no item ou no cartão); o clique continua fazendo o que
fazia. Todos têm a mesma cara: título e detalhe, às vezes um número grande e uma barra em partes,
seções de linhas (a linha clicável acende e leva ao lugar) e as ações no pé, cada uma um comando
do ⌘K. O cartão só lê enquanto está aberto.

| item | o cartão |
|---|---|
| CPU | o uso, usuário e sistema, a carga; os seus 5 processos mais ocupados; o que roda nos terminais do Cadex (o clique leva ao terminal). Os processos do sistema (WindowServer) só o Monitor de Atividade lê. |
| RAM | usado de total, apps/fixa/comprimida, a pressão de memória (o item fica âmbar fora de normal, vermelho em crítica); os 5 maiores processos |
| Cadex memory | o app, os ajudantes dele (engine da memória, daemon do terminal) e o que roda em cada terminal; o total. O número da barra continua só o app. |
| Ports | cada porta com o processo, o pid e o projeto; "Open" no preview; Stop a port… (ports.stop, SIGTERM) e Share on the tailnet… |
| Agents | os agentes de todas as janelas: precisa de você, trabalhando, pronto, parados; o clique leva ao terminal; o quadro e as notificações (agents.show-attention) |
| Terminals e Terminal ⌥⌘` | os terminais da janela e os da gaveta: o que roda, a pasta, há quanto tempo; novo terminal e a gaveta |
| Agent usage | o das contas, como antes; o clique troca de conta pelo mesmo cartão |
| Memory | quantas páginas, as que mudaram por último (lidas da wiki ao abrir); abrir e consolidar |
| Project | o branch contra o remoto (âmbar com algo a enviar ou receber), quantos arquivos mudaram, o último commit; Changes (na barra lateral), Push, trocar de branch |
| Folder | o que ocupa espaço na pasta (medido ao abrir, fora da thread principal; "measuring…" até lá) e o disco livre, âmbar abaixo de 10% |
| Environment | este Mac (macOS, processador, shell) e as outras máquinas da tailnet; Nova tarefa em… |
| Tailscale | as máquinas com online, caminho e latência (o ping só com o cartão aberto); o clique conecta |
| SSH | os hosts, como antes, sem o grupo Tailnet |
| Docker | o contexto e os contêineres rodando (o `docker ps` ao abrir) |
| Keep awake | ligado ou não, o modo, desde quando, até quando; desligar, com programa rodando, por 1 hora (power.keep-awake-hour) |
| Update | a versão nova e as primeiras novidades; atualizar e pular |

### Janela estreita e nada aberto (plano 38)
- Abaixo de 1000 pt a barra encurta: fica o primeiro item da esquerda e os dois primeiros da
  direita, cada um com a palavra; o resto vai para um "…", um menu com cada item (escolher faz o que
  o clique dele faz). Os lados salvos não mudam; alargar devolve a barra inteira.
- Sem projeto aberto, a barra mostra só o que vale sem projeto: a gaveta (Terminal ⌥⌘`), a conta
  (Agent usage), o café e o ambiente.

## Estados
- **Pasta desconhecida** (sessão ainda abrindo): Folder fica vazio, o resto aparece.
- **Dado ainda não lido** (Agent usage antes da primeira leitura): o item mostra só o ícone, apagado.
- **Nenhum item**: a barra continua com a altura dela, vazia; o botão direito ainda abre o menu.

## Casos de borda
- Itens demais para a largura: a trilha encolhe primeiro (pedaços do meio viram "…", a pasta atual
  nunca some); depois, os itens do fim de cada lado vão para um "…" que abre a lista num menu.
- Pasta sem permissão de leitura: o menu daquele pedaço fica vazio, com "Sem acesso".
- settings.json com item desconhecido ou repetido: ignorado, vira aviso; o resto vale.

## Critérios de aceite
- [ ] Sem configuração, a barra é a do mockup (StatusBar em `../design/work-frame/screens.md`).
- [ ] Uma barra personalizada antes da moldura nova continua a mesma depois.
- [ ] A trilha mostra a pasta do terminal com foco e muda ao trocar de aba e depois de um `cd`.
- [ ] Escolher uma subpasta no menu da trilha faz o terminal com foco ir até ela.
- [ ] Ligar RAM e CPU pelo botão direito mostra os dois na hora, em todas as janelas.
- [ ] No modo de edição, arrastar o SSH da direita para a esquerda muda o lado, e o settings.json
      guarda; reabrir o app mantém.
- [ ] Cada ação de personalizar também está no ⌘K.
- [ ] Com todos os itens novos escondidos, o `make perf` dá o mesmo de antes.

- "Terminal ⌥⌘`" (o item `drawer`, plano 30 C): o primeiro da direita por padrão, mostra ou esconde
  a gaveta de terminais; uma configuração de antes da versão 6 o ganha uma vez.

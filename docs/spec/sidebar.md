# sidebar

## Para que serve
A coluna à esquerda da janela: a árvore do trabalho. Os projetos, os terminais de cada um e as
tarefas quando existem, com o estado de cada coisa à vista, para saber onde se está e o que precisa
de você sem abrir página nenhuma (`../adr/0035-work-frame.md`; mockup e texto em
`../design/work-frame/screens.md`, seção Sidebar).

## Comportamento
- **Topo:** o botão "New task ⌘N" (abre a folha Nova tarefa, worktrees.new-task) e, ao lado, o botão
  de filtrar e agrupar (só os que precisam de você, só os trabalhando; agrupar por projeto, que é o
  padrão, ou por estado).
- **Projetos:** um cabeçalho por projeto (`projects.md`), dobrável pelo ▾, com o nome, o branch atual
  da pasta e quantas tarefas tem. Clicar no nome abre a página do projeto no centro, e o cabeçalho
  fica marcado enquanto ela está aberta. A ordem é a de criação; arrastar um projeto muda a ordem.
- **Dentro de um projeto, nesta ordem:**
  - os terminais da pasta do projeto (fora de tarefa), uma linha cada: ponto de estado, o nome (o
    do programa ou o dado à aba) e uma nota curta à direita (o modelo do agente, a porta que o
    programa abriu, o tempo de um comando);
  - as tarefas (worktrees do projeto), cada uma com a linha de tarefa abaixo.
- **Linha de tarefa**, em duas linhas:
  - a primeira: o estado (a peça única de estado do app: trabalhando, precisa de você, pronto,
    falhou, parado, em revisão), o nome da tarefa (o título do PR quando existe), a etiqueta de PR ou
    CI quando há (verde aberto, âmbar checagens falhando, roxo mesclado) e a idade (desde a última
    troca de estado);
  - a segunda: agente · conta, as linhas adicionadas e removidas da tarefa, e o que ela espera em
    âmbar ("approve Bash", "question").
  - Nome em negrito quando há novidade que o dono não viu (o agente terminou, pediu algo): sem
    número nem bolinha. Ver a tarefa tira o negrito.
  - Passar o mouse mostra o comentário da tarefa e os botões Go to Tab, Review e Hibernate; os
    sub-agentes de um agente dobram sob a linha.
- **A tarefa selecionada** (a da aba com foco) tem fundo e contorno, e embaixo dela os terminais
  dela, como os do projeto. Clicar num terminal mostra a aba dele; clicar na tarefa mostra a aba
  usada por último nela.
- "+ Add project" no fim da lista abre uma pasta como projeto (project.new).
- **Pé da coluna:** "Automations" com quantas estão ligadas e a próxima ("2 on · next 09:00"), que
  abre as automações no centro; e "Archive & history ⌘⇧H", que abre no centro as conversas dos
  agentes e as tarefas arquivadas.
- ⌘B recolhe e mostra a coluna. A largura padrão é 292 pt; arrastar a borda muda e fica salva.
- Projeto sem tarefa mostra só os terminais da pasta dele: o uso normal (abrir o projeto, um
  terminal com o Claude) nunca precisa de tarefa.
- A árvore não lê nada a cada tecla: muda com os avisos que já existem (estado dos agentes pelos
  hooks, worktrees criadas ou removidas, branch trocado, abas abertas ou fechadas).
- Toda ação da árvore é comando e está no ⌘K (ADR 0005): ir para um terminal, uma tarefa, um
  projeto; recolher; filtrar.

## Estados
- **Nenhum projeto:** a árvore mostra só "+ Add project" e o centro mostra a tela de início
  (`home.md`).
- **Projeto fora de um repositório git:** o cabeçalho sem branch; tarefas não se criam nele (a
  folha Nova tarefa só oferece "In the project's folder").
- **Pasta do projeto sumida:** o cabeçalho em cinza com "Folder not found" e Locate… e Remove.

## Casos de borda
- Muitas tarefas num projeto: as prontas há mais de um dia e sem novidade dobram em "N done" no fim
  do projeto.
- Nome longo: corta com reticências; o nome inteiro na dica.
- Tarefa de outra máquina ("Rodar em", plano 23): a linha mostra o nome da máquina junto da conta.

## Critérios de aceite
- [ ] Um projeto com dois terminais e uma tarefa mostra os dois terminais e a linha da tarefa; clicar
  num terminal mostra a aba dele.
- [ ] Um agente que pede permissão deixa a linha dele em âmbar, com o que espera, e o nome em negrito
  até o dono ver.
- [ ] Clicar no nome do projeto abre a página do projeto e marca o cabeçalho.
- [ ] Projeto sem tarefa nunca mostra nada de tarefa.
- [ ] ⌘B recolhe e mostra; a largura volta ao reabrir.
- [ ] Cada ação da árvore está no ⌘K.
- [ ] Nada da barra de antes existe: sem ícones de página, sem Customize Sidebar, sem a lista de
  ícones nas configurações (`../design/work-frame/inventory.md`).

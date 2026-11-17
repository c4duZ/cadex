# home

## Para que serve
A tela de onde tudo começa quando não há nada aberto: escrever o que quer fazer, ou abrir um
terminal, um agente, uma tarefa ou uma corrida, ou voltar a um projeto recente
(`../adr/0035-work-frame.md`; mockup e texto em `../design/work-frame/screens.md`, seção Home;
tokens components.home).

## Comportamento
- Aparece no centro quando nenhum projeto está aberto (a primeira abertura, ou depois de fechar o
  último) e pelo comando home.show (no ⌘K). Quem estava trabalhando abre o Cadex direto onde parou,
  sem passar por ela.
- A moldura é a de sempre: barra de título sem abas de terminal, a árvore à esquerda, o painel da
  direita fechado, a barra de status.
- **De cima para baixo**, numa coluna de 760 pt centrada:
  1. A saudação pela hora ("Good morning", "Good afternoon", "Good evening") e "Pick up where you
     were, or start something."
  2. **A caixa do pedido:** "What do you want to do in <projeto>?". O projeto é o da última vez (o
     ativo, ou o primeiro dos recentes) e o nome dele é um menu: os projetos abertos e os recentes,
     com busca, e Open folder… no fim. Escrever "@" na caixa abre o mesmo menu. Embaixo, o agente e a conta ("◆ Claude · bkdg ▾"; o menu lista as contas do Claude Code e as do
     Codex)
     e onde roda ("In this folder ▾", ou uma cópia separada, que vira tarefa); à direita, o que o
     Enter faz ("↩ opens a terminal with Claude"). Enter abre um terminal no projeto com o agente e
     a conta escolhidos, já com o pedido como prompt (`../adr/0036-owner-words-reach-the-agent.md`). Com "cópia separada", Enter abre a folha Nova tarefa já com o
     pedido.
  3. **Quatro cartões:** Terminal (⌘T, "A shell in the project's folder. Nothing else."), Agent
     (⌘⇧A, "A terminal already running Claude or Codex, in the account you pick."), Task (⌘N, "A
     separate copy on a new branch, so it works in parallel with you.") e Race ("The same task given
     to 2–3 agents; you keep the best.", que abre a folha Nova tarefa com duas linhas de agente).
     Cada cartão roda o comando dele.
  4. **Projetos recentes:** "RECENT PROJECTS" e, à direita, "Open folder ⌘O · Clone…"; uma linha por
     projeto (nome, caminho, estado em cor: âmbar quando algo precisa de você, verde quando um
     agente terminou, cinza sem nada aberto; e quando foi usado), os mais recentes primeiro, até 8.
     Clicar abre o projeto.
- Clone… pede o endereço do repositório e a pasta, clona pelo `git` do dono num terminal (a saída
  à vista) e abre a pasta como projeto.
- Nada é lido enquanto a tela não aparece; os estados dos recentes vêm do que a árvore já sabe.

## Estados
- **Sem projeto nenhum, nunca:** a caixa diz "What do you want to do?" sem projeto, e os cartões
  Terminal e Agent abrem na pasta pessoal; Task e Race pedem antes um projeto (Open folder).
- **Sem Claude Code instalado ou sem conta:** o cartão Agent e a caixa dizem "Add an account" e
  levam a adicionar conta (`agents.md`).

## Casos de borda
- Recente cuja pasta sumiu: a linha em cinza com "Folder not found" e Remove.
- Janela estreita: os cartões passam para duas colunas, depois uma.

- O Enter da caixa, conferido com um `claude` real (conta de teste, 2026-11-17): o projeto abre, o
  agente roda no terminal que veio com ele e responde ao pedido.

## Critérios de aceite
- [x] Sem projeto aberto, a tela de início aparece; com um projeto da última vez, o Cadex abre nele
      (2026-11-17, instância de teste aberta sem pasta).
- [x] Clone… clona num terminal e abre o projeto clonado (2026-11-17, um repositório local, no app).
- [x] Cada cartão roda o comando dele (terminal, agente, folha Nova tarefa, folha com dois agentes)
      (2026-11-17, no app, CADEX_PERF_HOME_ACTION e o relatório da janela).
- [x] Clicar num recente abre o projeto com as abas dele (o recente guarda as abas ao fechar).
- [x] Tudo da tela está no ⌘K (home.show e os comandos dos cartões).

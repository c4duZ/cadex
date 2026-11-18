# 0035 — A janela organizada pelo trabalho: árvore à esquerda, o aberto no centro, a seleção à direita

Data: 2026-11-17 · Status: aceita (o dono, 2026-11-17: "aprovo") · Revê a fileira de ícones de `docs/spec/sidebar.md` (plano 17)
e o botão de space de `docs/spec/spaces.md` · Planos `docs/plans/25-work-frame.md` a `docs/plans/30-overview.md`
· A esquerda e a direita foram revistas pela `docs/adr/0038-rail-and-side-column.md` (trilho e coluna lateral; a coluna da direita sai)

## Contexto
O dono testou o Cadex depois do plano 24 e achou a cara velha (2026-11-17): a fileira de ícones da
barra lateral não cabe, as sessões, os projetos e as páginas passivas (Memória, Histórico, Contas)
ficam escondidas, e não fica claro quando se está num terminal, numa tarefa, num projeto ou numa
corrida. Os mockups em `docs/design/work-frame/` (o canvas publicado em
https://claude.ai/artifact/USEjcwzEjAzLoJ16mBNtFo) foram aprovados por ele: "se ficar isso, é
lindo… muda tudo. Vamos tentar fazer isso".

Ele quer continuar no terminal (o Claude Code rodando nele, não uma interface própria por cima;
essa fica para depois) e quer os terminais e as abas no centro, divididos e movidos à vontade.

## Decisão
- **Uma moldura só, igual em toda tela**, em quatro regiões:
  - **Barra de título:** busca ⌘K, onde se está (projeto › tarefa), as abas do que está aberto
    (cada uma com o estado do que roda nela), o quadro, o sino e o botão do painel da direita.
  - **Esquerda, a árvore do trabalho:** os projetos e, em cada um, os terminais dele; uma tarefa
    aparece como um grupo de terminais só quando foi criada. No pé, Automações e Arquivo e
    histórico. É a única barra lateral; a fileira de ícones sai.
  - **Centro, o que se abriu:** os terminais (um ou divididos), o preview ao lado, a revisão, a
    página do projeto, o quadro, a corrida, a tela de início.
  - **Direita, a seleção (opcional, ⌥⌘I):** as abas Mudanças, Arquivos, Histórico e Memória do
    projeto ou da tarefa selecionada. As páginas Files, Git, Git History e Memory que hoje ficam na
    barra lateral passam para cá.
  - **Barra de status** embaixo, a mesma de hoje com outra cara.
- **Projeto é o space com pasta.** A spec de spaces já diz "um por projeto ou tarefa"; o space vira
  o projeto da árvore, com a pasta do repositório e as abas dele. O botão de space sai da barra de
  título; trocar de projeto é clicar na árvore ou ⌘J.
- **Tarefa e corrida nascem da mesma folha (⌘N):** onde roda (na pasta do projeto ou numa cópia
  separada, a worktree) e quem faz (um agente, ou mais, e aí é uma corrida com teto). Não há lugar
  separado para abrir corrida.
- **Estado tem uma cara só no app inteiro:** trabalhando (anel azul), precisa de você (âmbar com
  halo), pronto (verde), falhou (vermelho), parado (contorno). A peça é compartilhada.
- **O terminal do Claude é vestido, não substituído:** cabeçalho do painel (estado, tarefa, modelo,
  conta, custo, tempo), contorno de foco, respiro, cores do tema afinadas, a status line de uma
  linha (já é nossa), marcas dos turnos na barra de rolagem e o pedido de permissão como cartão no
  pé do painel quando vem pelo hook. O que o Claude desenha dentro dele continua sendo dele.
- **Fonte da interface: a do sistema (SF Pro).** Os mockups usam Inter por serem HTML; a do sistema
  é parecida e não pesa nem entra no NOTICE. O terminal continua com a fonte escolhida.

## Consequências
- Muda a casca de várias features (sidebar, tabs, status-bar, spaces, worktrees, orchestration,
  agents, themes) e a do app; o miolo delas fica. Seis planos (25 a 30), cada um tirando no mesmo
  plano o que substitui; o mapa peça por peça é `docs/design/work-frame/inventory.md`, e
  `tools/check_leftovers.py` (plano 25) falha no `make manifests` se uma peça tirada voltar.
- O app do Windows segue depois, com plano próprio; os comandos novos entram no `MAC_ONLY` da
  paridade até lá.
- Situação (2026-11-17): feita no Mac, planos 25 a 30, sem nenhuma linha do inventário em `sai`.
  O plano 31 refaz as telas que os mockups não desenharam; o 32 organiza as configurações; o 33 veste o painel do Claude e simplifica a troca de conta; depois falta só o Windows (plano 34) (`docs/plans/README.md`).
- Toda ação nova é comando (ADR 0005): abrir a tela de início, alternar o painel da direita, cada
  aba dele, a gaveta de terminais.

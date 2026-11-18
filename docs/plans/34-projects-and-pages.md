# Plano 34 — Projetos, sessões, memória e automações em páginas

O dono, 2026-11-18, depois de usar a dist: Automations não abria nada; clicar numa conversa do
Archive & history não mostrava nada dela; a sessão no painel Memory abria o .md cru; abrir o
Archive e voltar ao terminal mudava a barra de cima; as Configurações mostravam um projeto "cadu"
que ele não escolheu; e faltava uma página do projeto para ver as sessões e a memória. A proposta
aprovada ("Ficou do caralho... segue isso exatamente") está em
`docs/design/projects/proposta.html`, com um ajuste: a tela vazia de Automações maior, ocupando a
área, com o Criar automação no meio.

## O que eu quero
- A barra de cima mostrando só os terminais, sem mudar quando uma página abre. As páginas
  (Projetos, um projeto, Automações) abrem no centro, abaixo da barra; o Esc ou o clique numa aba
  de terminal volta a ela.
- O pé da barra lateral com Projetos e Automações; o Archive & history vira a aba Sessões de cada
  projeto (e continua no ⌘K, agents.show-history).
- A página do projeto com Visão geral, Sessões, Memória, Automações e Configurações dentro dela.
  As Configurações são as do projeto (plano 32, com a seção Memória do .ai-memory.toml), sempre do
  projeto da página.
- O clique numa sessão ou numa memória mostrando o resumo ao lado, renderizado, nunca o .md cru.
- Automações sempre abrindo: vazia, a tela inteira com o Criar automação no meio; com itens, a
  tabela.
- Cada tela igual à da proposta.

## O que eu não quero
- Página virando aba na barra de cima, ou trocando as abas dela (os extras "pages": Automations,
  Conversations, Settings).
- Um clique que não abre nada: comando indisponível escondido atrás de um item da barra lateral.
- Frontmatter, ids de sessão ou "process:ai-memory/3.4.7" à mostra no resumo.
- Feature importando o miolo de outra: a página do projeto recebe sessões, memória e automações
  do app, pelas portas de entrada delas.

## Como eu quero
- [x] A. As páginas fora da barra de cima: um documento de página não vira aba; uma página por vez
  no centro (abrir outra troca); o Esc e o clique numa aba voltam ao terminal de antes; o "+" e as
  abas iguais com a página aberta.
- [x] B. O pé da barra lateral com Projetos (o número) e Automações ("N ligada"), cada um aceso com
  a página dele aberta; a página Projetos: um cartão por projeto (nome, pasta e branch, tarefas,
  sessões, memórias, o que está acontecendo agora) e Adicionar projeto.
- [ ] C. A página do projeto com as seções num controle segmentado sob o cabeçalho ("Projetos ›
  nome", o nome, a pasta, o branch, as memórias e as sessões, Corrida… e Nova tarefa ⌘N). A Visão
  geral é a de hoje; Configurações, a página do projeto do plano 32 dentro desta.
- [ ] D. Sessões: a lista (título da conversa, a conta com o logo, a pasta, a idade) e, ao lado, o
  resumo da escolhida: o resumo e as tags da página de sessão da memória, o que foi feito, o que a
  memória guardou dela, Retomar, Continuar em outra conta… e Ver a página.
- [ ] E. Memória: a busca, as páginas agrupadas (Regras, Decisões, Cuidados, o resto) e, ao lado, a
  escolhida renderizada sem o frontmatter (o tipo, de qual sessão veio, a conta, o corpo); Editar
  (o .md no editor), Abrir a sessão e Apagar….
- [x] F. Automações: vazia, o ícone, "Nenhuma automação ainda", o exemplo e o Criar automação no
  meio da área; desligadas, o aviso de que criar a primeira as liga. Com itens, a tabela (ligar e
  desligar na linha, nome, quando, projeto, conta, a última e a próxima rodada); o clique na linha
  abre as rodadas; o botão direito tem Executar agora, Ligar ou desligar e Apagar, todos comandos.
- [ ] G. O painel Memory da direita leva a essas telas: o clique numa página ou sessão abre a página
  do projeto na seção dela com o item escolhido; "Todas no Archive" vira "Todas as sessões".
- [ ] H. Fechar: as specs (projects, sidebar, inspector, memory, orchestration), os CLAUDE.md, o
  `make check`, o `make perf` e a dist.

## Como validar
- Cada fase: os testes da feature, o print da instância de teste ao lado da tela da proposta, e a
  barra de cima conferida igual antes e depois de abrir e fechar a página.
- No fim, `make check` e `make perf`.

# projects

## Para que serve
Separar o trabalho por projeto (uma pasta de código, de preferência um repositório) e voltar a cada
um do jeito que estava, inclusive depois de fechar ou reabrir o app. É o que antes se chamava space,
agora sempre com a pasta (`../adr/0035-work-frame.md`).

## Comportamento
- Um projeto é uma pasta mais os terminais e documentos abertos nela, as tarefas dela (worktrees,
  `worktrees.md`), um nome (o da pasta, ou o que o dono der), uma cor opcional e uma imagem ou um
  emoji (plano 36 B).
- Os projetos aparecem no trilho, à esquerda (`sidebar.md`, ADR 0038), um quadrado cada. O centro
  mostra as abas do projeto escolhido (`tabs.md`); a coluna lateral fala dele (`inspector.md`).
- **Fixado:** o projeto fixado fica no trilho mesmo sem terminal; os outros saem quando o último
  terminal fecha. Criado pela folha, nasce fixado; aberto pelo ⌘O, não. Fixar e soltar pelo clique
  direito (project.pin), pelas Configurações do projeto ou arrastando para cima ou para baixo da
  linha do trilho. Um arquivo de antes do plano 36 volta com tudo fixado.
- **Abrir um projeto:** o "+" do trilho (project.create, a folha com a pasta, o nome, a imagem e a
  cor), Open folder (⌘O, project.new) e os recentes da tela de início (`home.md`), `cadex .` num
  terminal, ou soltar a pasta no ícone do Dock. Abrir a pasta de um projeto que já existe vai para
  ele. Os terminais da pasta pessoal não viram projeto (abas sem projeto).
- **Trocar de projeto:** clicar nele no trilho, project.switch (⇧⌘S, a lista na paleta com a imagem
  e a busca, o atual marcado), project.next (⌃⌘→) e project.previous (⌃⌘←), dando a volta; e o ⌘J,
  por atenção. O foco volta para onde estava no projeto.
- **Editar:** project.edit (Edit Name and Image…, no clique direito, nas Configurações do projeto e
  no ⌘K) abre a folha com o nome (vazio volta ao da pasta), a imagem (Choose Image…, Remove; ou solta
  no quadrado), o emoji e a cor, com a prévia como o trilho mostra. project.rename e
  project.set-color continuam no ⌘K; a cor pinta o quadrado e a barra de abas enquanto o projeto
  aparece (`themes.md`, cores de trabalho).
- project.close encerra os terminais e documentos do projeto (pergunta antes se algum roda um
  programa ou se há arquivo não salvo) e tira o projeto do trilho; Close Terminals fecha os
  terminais e deixa um fixado no trilho; Remove from the Sidebar solta e fecha. As tarefas e as worktrees ficam
  no disco e voltam se a pasta for aberta de novo. Fechar o último projeto mostra a tela de início.
  Um projeto fechado fica nos recentes com as abas que tinha, e reabri-lo (pela tela de início ou
  pela pasta) as devolve.
- Os programas dos projetos que não aparecem continuam rodando; só não desenham.
- **Ao reabrir o app**, cada projeto volta com as abas na mesma ordem, os nomes dados às abas, as
  divisões com as proporções, a pasta de cada painel, os arquivos e o histórico do git abertos (em
  aba própria ou num painel ao lado de um terminal), o painel com foco, e o projeto e a aba que
  estavam ativos. Com terminal.keepSessions desligado (o padrão), o conteúdo antigo do terminal não
  volta: cada painel começa um shell novo na pasta salva. Ligado (plano 19), cada painel religa ao
  shell que o daemon do terminal manteve, com a tela e o scrollback; depois de reiniciar o Mac,
  volta o scrollback salvo, num shell novo.
- O estado é salvo sozinho, logo depois de cada mudança (abrir, fechar, dividir, mudar de pasta,
  trocar de projeto), num arquivo em Application Support/Cadex. Fechar o app de surpresa perde no
  máximo o último meio segundo.
- Abrir o app com uma pasta ou arquivos na linha de comando restaura os projetos e abre o que foi
  pedido (a pasta vira o projeto dela, com uma aba de terminal; arquivos abrem no projeto ativo).
  Abrir sem nada (pelo Dock) volta ao projeto ativo da última vez.
- **Os spaces de antes viram projetos uma vez**, na primeira abertura com a moldura nova: cada space
  vira o projeto da pasta do workspace dele, com as abas, o nome e a cor; dois spaces da mesma pasta
  viram um projeto com as abas dos dois, na ordem. O arquivo velho fica ao lado, com outro nome, até
  o plano seguinte.

## Estados
- **Primeira abertura (sem arquivo):** nenhum projeto; a tela de início.
- **Arquivo ilegível:** como a primeira abertura; o arquivo ruim fica ao lado, com outro nome, para
  não se perder.

## Casos de borda
- Pasta de um painel apagada entre as sessões -> o shell abre na pasta do projeto, ou na pessoal se
  ela também sumiu.
- Pasta do projeto apagada -> o quadrado fica, sem aviso próprio ainda (o Locate… da árvore de
  antes saiu com ela); Remove from the Sidebar o tira.
- Arquivo aberto que sumiu -> a aba dele não volta; num painel dividido, o painel vira um terminal
  na pasta do arquivo, para o layout não mudar. O resto volta.
- Diff, preview web e janelas de mensagem não são restaurados (são passageiros).
- Projeto salvo sem nenhuma aba -> volta com um terminal na pasta dele.
- Dois projetos com o mesmo nome (pastas diferentes) -> permitido; a paleta mostra o caminho e o
  trilho, a imagem ou a cor de cada um.

### A página do projeto (mockup Project; plano 30 A, feito junto da revisão do plano 29)
- Um cartão da página Projetos, project.show-overview no ⌘K, ou o clique numa conversa ou página da
  coluna lateral abre a página no centro, abaixo da barra de cima, que não muda (plano 34; a
  proposta em `docs/design/projects/proposta.html`); a coluna lateral fica (ADR 0038); o Esc ou uma
  aba de terminal saem dela.
- Em cima, "Projects › nome" (o primeiro leva à página Projetos), a imagem do projeto, o nome, a
  linha "caminho · branch · remoto · N páginas de memória · N sessões", Open terminal (os terminais
  do projeto, um aberto se não há), Race… e New task, e as seções num controle sob o
  cabeçalho: Visão geral (o que segue), Sessões, Memória, Automações e Configurações.
- Sessões: as conversas do projeto e das tarefas dele, com a conta (o logo), a pasta e a idade; a
  escolhida mostra ao lado o resumo da página de sessão da memória, as tags, o corpo, o que a memória
  guardou dela, Retomar, Continuar em outra conta… e Ver a página (já renderizada).
- Memória: a busca e as páginas agrupadas (regras, decisões, cuidados, padrões, outras) com o
  sinal do tipo; a escolhida aparece renderizada, sem o frontmatter (o tipo, de qual sessão veio, a
  conta, o corpo), com Editar (o .md no editor), Abrir a sessão e Apagar…. O clique numa página da
  Memory da coluna lateral, ou na busca da memória do ⌘K, abre aqui.
- Automações: as do projeto, com o liga e desliga, Criar automação e a página de todas;
  Configurações: no topo, "In the sidebar" (a prévia, Edit Name and Image… e a caixa de fixado,
  plano 36 E), depois a memória do projeto (o .ai-memory.toml, plano 32).
- A página Projetos (project.show-all, o pé do trilho): um cartão por projeto com a imagem, a pasta
  e o branch, tarefas, sessões, memórias e o que acontece agora; o cartão abre a página do projeto.
  Ela não edita nada (ADR 0038); Add project é o mesmo "+" do trilho.
- De cima para baixo: o nome, o caminho · o branch · o remoto, e Race… e New task; quatro números
  (tarefas abertas com quantas trabalham e quantas precisam de você; o gasto da semana pelo custo
  que a status line gravou de cada sessão, com sessões e contas; os merges dos últimos 30 dias,
  "N PRs" quando vêm de pull requests, e o último; as páginas da memória e as de hoje, ou "off");
  as conversas recentes do projeto e das tarefas dele (as abertas fora do Cadex também, pelo
  arquivo e histórico), com o estado, a tarefa, o agente e a conta; as automações do projeto com o
  liga e desliga (o mesmo orchestration.toggle-automation, que pergunta ao ligar); as contas
  usadas ali nos últimos 30 dias, com o uso em âmbar acima de 80%.
- Responsiva: os números em 4, 2 ou 1 coluna pela largura; as duas colunas lado a lado ou uma
  embaixo da outra abaixo de 720 pt, com os botões sob o nome; a página rola.
- Clicar numa conversa viva traz o terminal dela; numa terminada, continua numa aba da pasta dela.

## Critérios de aceite
- [x] Um projeto salvo e restaurado volta igual: abas, nomes, divisões com proporções, pastas, foco.
  (Conferido com os projetos: o teste "projects saved and restored come back the same".)
- [x] Arquivo de estado corrompido não impede o app de abrir: volta ao padrão e guarda o ruim ao lado.
- [x] Trocar de projeto pelo trilho, pela paleta e pelos atalhos mostra as abas daquele projeto.
- [x] O nome, a imagem, o emoji e a cor editados voltam ao reabrir; a imagem trocada sai da pasta.
- [x] Um fixado sem terminal fica no trilho; solto e sem terminal, sai.
- [x] Fechar o app pelo menu e reabrir traz os mesmos projetos e o mesmo projeto ativo.
- [x] Um terminal e um documento lado a lado voltam lado a lado.
- [ ] Com terminal.keepSessions ligado, reabrir o app traz a tela e o scrollback de cada painel;
      depois de reiniciar o Mac, o scrollback salvo volta num shell novo.
- [x] Os spaces de uma instalação de antes voltam como projetos, com as abas, depois da migração (plano 27; a leitura do spaces.json saiu no 28, depois de migrar).
- [x] Nenhum comando space.* existe depois do plano 28 (`../design/work-frame/inventory.md`).

# As telas da página Memória, descritas

Continuação de `docs/design/work-frame/screens.md` para o plano 40 (`docs/plans/40-memory-panel.md`):
o painel do ai-memory 3.5.0 refeito nativo, uma seção por mockup `Memory*.dc.html`. Cada seção diz o
que a tela mostra, na ordem, o que cada clique faz e, em "Cortes" e "Divergências", tudo o que saiu
ou mudou em relação ao print do upstream (`docs/research/memory-panel-screens.md`), para o dono
pesar fidelidade contra brevidade. Escrito em 2026-11-19.

### MemorySidebar.dc.html — peça · A página Memória: a barra lateral e as seções (plano 40)
- **Os textos das telas Memória estão em português**, como os prints do upstream (pt-BR), para
  comparar um a um; no app cada texto é um par inglês/português (ADR 0015) e o padrão é o inglês.
- **À esquerda, a barra lateral de sempre** (components.workSidebar), na vista Trabalho, com
  Memória acesa no pé, depois de Quadro, Automações e Máquinas. O clique em Memória abre a página
  no centro, na Visão geral (ou na última seção vista).
- **Ao lado, a coluna das seções da página** (200 pt, fundo da janela, fio à direita), o menu da
  esquerda do upstream nos mesmos grupos e na mesma ordem:
  1. O campo "Pesquisar na memória" (num projeto, "Pesquisar em cadex"): Enter abre Pesquisar com
     o termo (e o escopo do projeto). Era a busca do cabeçalho do upstream.
  2. ESPAÇO DE TRABALHO: Projetos, Caixa de entrada (com o número de mensagens na fila à direita,
     só quando há), Workstreams, Pesquisar, Grafo.
  3. OBSERVAR E MELHORAR: Revisão de aprendizado, Saúde.
  4. RECURSOS: Documentação, Histórico de alterações (abre o changelog na mesma tela da
     documentação, com o seletor de versão; sem board próprio).
  5. No pé, "ai-memory 3.5.0".
  O item da seção aberta fica com o fundo da linha escolhida; dentro de um projeto (a página, o
  histórico, a sessão, o agente, o grafo do projeto) fica aceso Projetos, como no upstream.
- **Por que uma coluna, e não abas no topo da página:** são nove destinos em três grupos, com um
  contador vivo na Caixa de entrada; um seletor segmentado do macOS cabe até uns cinco itens e
  perderia os grupos. A coluna repete o menu do upstream (fidelidade direta, item por item) e é o
  padrão de "barra de fontes" do macOS (Mail, Ajustes); a barra lateral do Cadex continua igual,
  com Memória acesa, para voltar ao trabalho num clique.
- **Cortes do upstream na moldura:** a marca ("ai-memory", "ESPAÇO DE TRABALHO DOS AGENTES"), o pé
  "Contexto que permanece. Entre agentes. Entre sessões.", a legenda "Espaço de trabalho /
  Operações dos agentes", o rodapé "ai-memory · Memória do projeto e operações dos agentes" (fica
  só a versão), Sair, o idioma, o tema Claro/Escuro/Sistema (segue o Cadex), o filete em degradê e
  o painel de projetos com fila embaixo da Caixa de entrada (o número basta; os projetos estão na
  tela da caixa).
- **Divergências comuns a todas as telas** (cada tela lista só as suas):
  - Sobretítulos laranja em caixa alta ("VISÃO GERAL DO ESPAÇO DE TRABALHO", "ESPAÇO DE TRABALHO DO
    PROJETO", "MANTENHA O TRABALHO EM ANDAMENTO"…) caem: o título basta.
  - O botão principal é o claro do Cadex, não o laranja do upstream; links em azul (accent.link),
    não em verde.
  - A trilha usa "›" e omite o workspace quando é "default" ("Projetos › cadex", não "Projetos /
    default / cadex"); um workspace diferente aparece.
  - Números com separador de milhar em português (86.023, não 86023), menos onde o valor é técnico
    (a Saúde mostra os números como o upstream).
  - Frase explicativa longa vira uma linha curta ou um ⓘ com a frase inteira no tooltip.

### MemoryOverview.dc.html — Memória · Visão geral (print 01)
- **Cabeçalho:** "Painel de memória"; à direita "Abrir caixa de entrada" → seção Caixa de entrada.
- **Cinco números** (os cartões da página do projeto, components.memoryPanel.stat): Projetos 5,
  Sessões 201, Eventos capturados 86.023, Páginas compiladas 196, Sessões abertas 0 (em âmbar). O
  clique em cada um ordena os cartões abaixo (sessões, eventos, páginas; Sessões abertas filtra
  as com sessão aberta), como os links do upstream; Projetos rola até a lista.
- **Linha da captura:** "Última captura: há 9 horas ⓘ" e, se o engine tem métricas, "Captura: 0
  aceitos · 0 descartados pela política · 0 por capacidade · 0 limitados por taxa" (o bloco "Saúde
  da captura dos hooks" do upstream, que no print não aparece por falta de métricas).
- **Aviso da fila** (não desenhado: o dono não tem fila): com mensagens na fila, uma faixa âmbar
  (components.memoryPanel.notice) "N mensagens aguardando agentes em projeto (n), …" (até 5),
  entre a linha da captura e os projetos; o clique abre a Caixa de entrada.
- **"Seus projetos" 5**, o campo "Filtrar projetos…" e o seletor "Todos os projetos ▾" (Com
  sessões abertas, Com mensagens na fila). Filtrando: "N de M"; nada: "Nenhum projeto corresponde
  a estes filtros".
- **Cartões em três colunas:** a marca, o nome, os agentes ("Claude Code" ou "Nenhuma sessão de
  agente ainda"); quatro números (Sessões, Eventos capturados, Páginas compiladas, Sessões
  abertas); no pé "Última captura: há 9 horas" (ou "Nenhuma captura ainda"), "Agentes ↗" (a aba
  Agentes do projeto) e "Abrir no Cadex" (o projeto do Cadex com a mesma pasta; some quando não
  há, como em _global e scratch). Com fila, o selo "N caixa de entrada" ao lado do nome. O clique
  no cartão abre o projeto (MemoryProject).
- **Cortes:** a linha "Acompanhe a atividade, investigue o uso de tokens e coordene seus agentes.";
  as notas dos números ("Visíveis no seu espaço de trabalho", "Projetos com mais sessões
  primeiro"…), que viram tooltip; a nota da captura ("Aberta significa que nenhum SessionEnd foi
  recebido; pode ser um agente ativo ou uma interrupção. Os contadores contêm apenas metadados;
  prompts e comandos brutos permanecem nas visualizações detalhadas do escopo."), no ⓘ; o
  workspace "default" em mono no cartão; "páginas" depois do número; "Explorar agentes" vira
  "Agentes"; a dobra "Sobre a memória compilada" (o texto está na Documentação); o diálogo da
  migração OKF.

### MemoryProject.dc.html — Memória · Um projeto (print 09)
- **Trilha** "Projetos › cadex"; título "cadex"; à direita "Abrir no Cadex" (o projeto no Cadex) e
  "Mensagem a um agente" (Caixa de entrada, com o projeto preenchido).
- **Abas** no seletor segmentado: Visão geral, Agentes, Uso de tokens, Sessões, Conhecimento; à
  direita "Caixa de entrada ↗" e "Grafo de links ↗" (MemoryGraph).
- **Visão geral:** cinco números: Sessões 44, Eventos capturados 15.098, Páginas compiladas 49,
  Sessões abertas 0 (âmbar), Tokens (entrada / saída) —; a linha "Última captura: há 9 horas ·
  nenhuma sessão aberta" e, à direita, "Agentes" com o selo roxo "● Claude Code · 44" (→ o
  agente); a caixa "Caixa de mensagens" com "Nenhuma mensagem pendente." e "Abrir caixa de
  entrada" (com mensagens: assunto, "de projeto", trecho e quando, uma por linha).
- **Aba Conhecimento** (desenhada embaixo, separada pelo rótulo "ABA CONHECIMENTO"; sem print no
  upstream): à esquerda PÁGINAS, a árvore por pasta com a contagem (_rules/ 2, decisions/ 1,
  gotchas/ 2) e "Sistema" mais apagado (_lint/, sessions/ 43; a contagem de _lint/ é de exemplo);
  à direita ATIVIDADE RECENTE, uma linha por página (título, caminho · agente, o tipo, quando; os
  itens são de exemplo). O clique numa página abre MemoryPage.
- **Abas sem desenho**, como o HTML do upstream: Agentes (um cartão por agente, o mesmo da tela
  MemoryAgent, "1 registrado"); Uso de tokens (a caixa de uso de MemorySession, para o projeto);
  Sessões (a tabela de MemoryAgent com a coluna Agente, filtros só abertas e por eventos).
- **Cortes:** "Entenda seus agentes, examine suas sessões e encontre chamadas de alto consumo.";
  o título da seção "VISÃO GERAL / Visão geral do projeto" e "Captura, atividade e mensagens
  pendentes. Escolha uma aba para explorar os detalhes."; as notas dos cinco números ("Atividade
  registrada", "Sessões mais movimentadas primeiro", "Conhecimento para consulta", "Somente
  sessões não encerradas", "Totais de sessões informados"), no tooltip; "Nenhuma sessão aberta
  registrada no momento." vira "nenhuma sessão aberta".

### MemoryPage.dc.html — Memória · Uma página (print 10)
- **Trilha** até o caminho cortado; o título da página; os selos "● semantic" (camada, verde) e
  "decision" (tipo), fixada e expirada quando for; "Atualizada há 1 dia · Histórico · Criada há 1
  dia" (Histórico → MemoryHistory); "substitui …" e o autor quando há.
- **Caixa "Evidências e validade"** (aberta), uma linha por item com nome e valor curto e ⓘ:
  Versão (o id em mono), Expiração "Sem expiração registrada", Fontes acessíveis "0 citações
  registradas" (com fontes: a lista paginada embaixo), Contradições declaradas "0 conexões
  ativas" (com contradições: a lista); a dobra "Por que esta página foi recuperada?".
- **O Markdown** renderizado pela feature markdown; um link de página abre a página aqui.
- **Coluna da direita:** "Nesta página" (só com títulos), CITADA POR ("Nenhuma página aponta para
  cá." ou a lista com "e mais N"), "Cita" (só com links).
- **Cortes** (todos no ⓘ da linha): "As evidências se aplicam a esta versão indexada. Citações
  registradas não comprovam a veracidade."; "a validade não é verificada de forma independente";
  "A ausência de registros indica informação desconhecida, não falta de fundamento. As fontes
  podem estar indisponíveis, ser privadas ou não estar mais retidas."; "no máximo 20 exibidas. São
  relações declaradas, sem julgamento de correção. A ausência não comprova consistência.". O título
  da caixa encurta de "Evidências e validade do conhecimento" para "Evidências e validade".

### MemoryHistory.dc.html — Memória · O histórico de uma página (print 11)
- **Trilha** até "histórico"; título "Histórico" e, embaixo, o caminho em mono e "1 versão, a mais
  recente primeiro ⓘ".
- **O diff:** "Conteúdo de 5ef7d2d8 · nenhuma versão anterior" (ou "Alterações de X para Y"), o
  título, e o bloco mono com o cabeçalho do hunk e as linhas + em verde (− em vermelho); "mesmo
  corpo", "grande demais" e "cortado no limite" como texto no lugar do bloco.
- **"Versões 1–1 de 1":** a tabela De e Para (rádios), Versão (id curto e o selo "mais recente";
  "substituiu X" quando há), Gravação, Autor, Título, Tamanho ("386 caracteres"), e "Comparar
  selecionadas"; "Versões mais novas / mais antigas" com mais de uma página.
- **Cortes:** o título "Histórico de decisions/…md" vira "Histórico" com o caminho embaixo (o
  caminho longo quebrava em 22); "Versões substituídas permanecem no registro; nada aqui pode
  alterá-las." no ⓘ; a coluna "vs. anterior" (vazia no print) entra só quando há anterior.

### MemorySession.dc.html — Memória · A linha do tempo de uma sessão (print 12)
- **Trilha** "Projetos › cadex › sessão 1301a3b0…" e, à direita, "← Sessões de claude-code" (o
  agente, MemoryAgent) e "Recuperações".
- **Título** "Linha do tempo da sessão"; o selo do agente e "iniciada 18/11 21:13:34 · encerrada
  19/11 02:46:59 ⓘ" (ou "ainda aberta"); à direita "Abrir no Cadex": o terminal onde a sessão
  roda, se aberta, ou um terminal novo que retoma a conversa do Claude Code (cwd e id da sessão).
- **Uso de tokens** numa caixa: o título, o selo "Durante as sessões", "0–0 de 0 respostas" e
  "Filtrar…"; os seis números (Chamadas capturadas, Entrada nova, Saída, Leitura do cache,
  Gravação no cache, Entrada do cache); com respostas, a tabela delas embaixo (resposta/sessão,
  modelo, entrada, saída, cache, total, sinal); sem: "Nenhum uso de resposta informado ainda ⓘ".
- **A barra de páginas:** « Primeira, ‹ Anterior, "1–50 de 882", Próxima ›, Última », e "Ir para"
  com o controle deslizante, o número e "Ir"; j/k e as setas andam uma observação.
- **As observações**, uma caixa cada: "#n", o selo do tipo (session-start, user-prompt, other…),
  o título, "há 23 horas" e o corpo em mono, cortado.
- **Recuperações** (print 15, sem board): a mesma moldura, "‹ Linha do tempo da sessão", título
  "Histórico de recuperações" e "Nenhuma recuperação registrada para esta sessão."; com registros,
  a mesma barra de páginas e uma caixa por consulta (escopo, quando, a consulta em mono,
  resultados, limite, duração, e os acertos com caminho → página).
- **Cortes:** "Observações capturadas, em ordem. Foram sanitizadas na captura e são exibidas como
  texto simples." e quantas ficaram em outro projeto, no ⓘ do horário; o horário ISO com
  milissegundos vira dia/mês e hora local (o ISO no tooltip); "ACOMPANHE O CONSUMO" e "Respostas do
  modelo medidas · uso atualizado a cada 10 segundos"; os dez campos de filtro (busca, todas as
  respostas / sinais, ordem, De e Até, Modelo, Cliente de agente, ID da sessão, ID do turno,
  Ferramenta) vão para "Filtrar…" (um popover com os mesmos campos); as duas frases do vazio
  ("Clientes atualizados do Claude Code e do Codex informam o uso…", "Os totais das sessões
  existentes continuam visíveis…") e a nota longa do pé ("As datas usam o horário informado…
  Uso não informado é desconhecido, nunca zero.") vão para o ⓘ.

### MemoryAgent.dc.html — Memória · Um agente num projeto (print 13)
- **Trilha** "Projetos › cadex › Claude Code"; título "Claude Code" e "Sessões, consumo e cobertura
  em cadex"; à direita "Mensagem ao agente".
- **Quatro números com nota curta:** Sessões registradas 44 "0 sem evento de encerramento";
  Tokens informados — "entrada + saída + cache"; Chamadas medidas 0 "respostas deste agente";
  Cobertura de uso 0% "0 de 44 sessões".
- **Faixa âmbar** (só com cobertura abaixo de 100%): "Há uma lacuna de visibilidade · 44 sessões
  sem uso informado ⓘ".
- **SESSÕES:** a tabela Sessão (id curto em mono, ↗ abre MemorySession), Estado (o selo
  "Encerrada" com ponto cinza; "Aberta" com ponto azul), Início, Duração, Eventos, Tokens · entrada
  / saída; na linha sob o ponteiro, "Abrir no Cadex" à direita (o terminal ou a retomada, como na
  sessão). "Mais novas / Mais antigas" no fim.
- **Cortes:** "INFORMAÇÕES DO AGENTE · default"; "Sessões, consumo e cobertura de captura de
  cadex." encurta; "Atualize o cliente e os hooks deste agente para capturar as respostas do
  modelo durante o trabalho." vai para o ⓘ da faixa; "ATIVIDADE" e "Abra uma sessão para examinar
  as respostas capturadas e a linha do tempo de eventos.".

### MemorySearch.dc.html — Memória · Pesquisar (print 04)
- **Título** "Pesquisar: memória" com o termo em verde; num projeto, o selo "em cadex ×" ao lado
  (× volta à busca geral).
- **A barra:** os seletores Todos os projetos (e os projetos), Qualquer tipo, Qualquer camada; o
  campo com o termo (com foco); "Explicar classificação"; "Pesquisar".
- **"34 resultados"**, e um resultado por bloco: o título (seminegrito), o trecho numa linha com o
  termo marcado em âmbar, e "projeto · caminho". O clique abre a página (MemoryPage).
- Com "Explicar classificação": a caixa "Rastro da recuperação" acima dos resultados e, em cada
  um, posição, rank e a tabela dos streams, numa dobra.
- Vazio: "Nenhum resultado para X" e "Pesquisar em todos os projetos"; sem termo, as páginas
  recentes.
- **Divergências:** o título do resultado em branco, não em verde (o verde fica só no termo do
  título, como destaque); o trecho numa linha só (o upstream quebra em duas); o workspace "default"
  sai do "default/cadex".

### MemoryGraph.dc.html — Memória · O grafo de links (prints 14 e 05)
- **O do projeto** (desenhado, aberto por "Grafo de links ↗" no projeto): trilha "Projetos › cadex
  › grafo", título "Grafo de links de cadex", "49 páginas mais recentes · 0 links entre elas"; à
  esquerda o quadro de 600 com as 49 páginas num círculo (o circular_layout do upstream), as
  arestas como linhas; à direita CONEXÕES (De → Para, uma por linha; "Nenhum link resolvido.").
  Aviso âmbar quando cortado no teto de nós.
- **O geral** (o item Grafo da coluna, sem desenho): título "Grafo de links", "Links entre
  projetos" e, nos dados do dono, "Ainda não há links entre projetos." e "Nenhum link resolvido."
  em CONEXÕES.
- **Divergência:** os títulos das páginas não ficam escritos em volta do círculo (no upstream se
  sobrepõem e não se leem); aparecem num balão sobre o nó sob o ponteiro (título e caminho), e o
  clique abre a página.
- **Cortes:** "Páginas mais recentes deste projeto e os wikilinks resolvidos entre elas." vira os
  números; "Wikilinks resolvidos cujas extremidades estão em projetos diferentes. Uma conexão só
  aparece quando as duas extremidades podem ser lidas." vira "Links entre projetos" com o resto
  no ⓘ.

### MemoryInbox.dc.html — Memória · Caixa de entrada (print 02)
- **Título** "Caixa de entrada dos agentes" e, embaixo, o estado da fila: "Nenhuma mensagem
  aguardando agentes" (com fila: "N na fila · M projetos" e um link por projeto). À direita "Nova
  mensagem" (põe o foco no formulário).
- **À esquerda, a caixa do projeto:** o seletor do projeto ("cadex", com "· n" na fila), Recebidas
  | Enviadas, e o estado (Todas as mensagens, Aguardando coleta, Coletadas, Canceladas, Em
  edição). Cada mensagem numa linha que abre: envelope, assunto, "origem → destino", "agente ·
  quando", o selo do estado; aberta, o corpo, o id e Editar (ou Continuar editando / Descartar
  alterações). Vazio: "Um pouco de tranquilidade" e "Nenhuma mensagem neste estado.".
- **À direita, Nova mensagem:** Do projeto, Para o projeto ⓘ, Para o agente ⓘ ("Selecione um
  agente registrado…"; só os registrados no destino), Assunto (opcional), Mensagem ("Descreva o
  pedido, o contexto e o resultado esperado."), "Texto simples · segredos são removidos" e "0 /
  8.000", "Fica na fila até a próxima verificação do agente ⓘ" e "Colocar na fila"; o resultado
  aparece no lugar da nota, com "Ver enviadas".
- **Cortes:** a trilha "Projetos / default / cadex / Caixa de entrada" e "Caixa de mensagens:
  default / cadex" (o seletor do projeto já diz); a caixa "Aguardando agentes" vira a linha sob o
  título; "Nenhuma mensagem aguardando agentes nos projetos aos quais você tem acesso." encurta;
  "Escolha um agente e deixe uma solicitação clara para a próxima verificação da caixa de
  entrada." sai do vazio; "DIRETO PARA UM AGENTE"; as dicas "Por padrão, o projeto de origem.
  Escolha outro projeto para enviar uma mensagem entre projetos." e "Somente agentes registrados no
  projeto de destino são exibidos." vão para o ⓘ; "Na fila para a próxima verificação da caixa de
  entrada deste agente. Enviar uma mensagem não inicia um agente nem executa seu conteúdo." encurta
  (o resto no ⓘ); o campo de token de escrita (o app fala pelo socket). "Colocar mensagem na fila"
  vira "Colocar na fila".

### MemoryWorkstreams.dc.html — Memória · Workstreams (print 03)
- **Título** "Workstreams gerenciados", "Por atenção e atividade recente" e "Página 1" à direita.
- **A tabela:** Workstream (o nome; o projeto como link e o id curto em mono), Estado (selo: verde
  ativo, âmbar interrompido, neutro nos outros), Execução mais recente (o selo do agente, o id
  curto, "Início há 1 dia[, fim …]" ou "Não iniciado"), Evidências ("0 evento" e os selos dos
  harnesses), Atividade (à direita). "Anterior / Próxima" com mais de uma página; vazio "Nenhum
  workstream gerenciado nesta página.".
- **Cortes:** "Estado operacional entre projetos, ordenado por necessidade de atenção e atividade
  recente." encurta; "default/bkdg-center" vira "bkdg-center".

### MemoryReview.dc.html — Memória · Revisão de aprendizado (print 06)
- **Título** "Gravações pendentes" e "Propostas de melhoria automática à espera de decisão".
- **Filtros:** Projeto ("Todos os projetos (0)" e um por escopo com a contagem) e Ordenação
  (Projeto e depois data de envio; Confiança, menor primeiro; Confiança, maior primeiro; Envio,
  mais recente primeiro); à direita "0 exibidas · 0 pendentes em 0 projeto".
- **Vazio:** "Nenhuma proposta pendente". Com propostas, uma linha por proposta que abre: título,
  o selo da operação (âmbar se reescreve uma página), "regra" se é de _rules/, o tipo; escopo,
  caminho, "confiança N%", "enviada há X"; aberta, os avisos, Justificativa, Corpo proposto, o id,
  e Aprovar / Rejeitar com o motivo.
- **Divergências:** sem o botão Aplicar (o seletor aplica ao escolher, como no macOS); sem os
  comandos POSIX e PowerShell do login só de leitura (no Cadex o dono aprova pelo app).
- **Cortes:** "Abra uma proposta para lê-la e depois aprove ou rejeite."; a dica da CLI no corte
  de 500.

### MemoryHealth.dc.html — Memória · Saúde (print 07)
- **Título** "Saúde do servidor" e "Somente leitura: cada correção é um comando".
- **Faixa âmbar** quando os contadores do processo não estão ligados: "Contadores de hooks, spool e
  provedores não ligados a este painel".
- **Verificações:** "● Todas as verificações do servidor passaram" em verde, ou a lista (erro em
  vermelho, aviso em âmbar, cada um com "Correção:" e o comando).
- **As seções em caixas, em duas colunas**, cada linha o nome e o valor em mono (o valor quebra
  linha, nunca corta): HOOKS (DESDE O INÍCIO DO SERVIDOR), GRAVAÇÃO, SPOOL E RECUPERAÇÃO,
  CONSOLIDAÇÃO à esquerda; EMBEDDINGS E MODELOS, ÍNDICE E ARMAZENAMENTO à direita. Os valores
  como os do upstream.
- **Cortes:** "Contadores, filas e estado dos modelos deste processo do servidor." sai; "Este
  servidor não conectou seus contadores de processo à interface web; os dados de hooks, spool e
  provedores abaixo estão vazios." encurta; "pendente mais antigo desde" vira "pendente mais
  antigo".
- **No Cadex:** hooks, spool e provedores são do servidor do upstream; a fase B decide se essas
  linhas mostram os contadores do engine ou caem (o inventário, seção 7).

### MemoryDocs.dc.html — Memória · Documentação (print 08)
- **Título** "Documentação" e, à direita, "Histórico de alterações".
- **Destaque:** "Comece pelo guia de ativação" com o selo "versão 3.5.0" e "Pré-requisitos,
  configuração e verificações"; "Explorar recursos" abre o guia de recursos (com "Estado efetivo
  da instalação").
- **Busca** "Buscar recurso, comando ou chave de configuração…" (filtra ao digitar) e "28 guias ⓘ".
- **Os guias** em três colunas: a categoria (COMECE AQUI, FLUXOS DE AGENTES, APRENDIZADO E
  RECUPERAÇÃO, ACESSO E INTEGRAÇÃO, OPERAÇÕES), o título e uma linha de descrição. O clique abre o
  guia na mesma página (o Markdown pela feature markdown, "Nesta página" à direita, "Ler Markdown").
- **Cortes:** "APRENDER E CONFIGURAR"; "Entenda cada recurso, habilite o que precisa e verifique se
  funciona."; o texto do destaque ("Pré-requisitos, etapas de configuração e verificações de
  captura, tokens, caixa de entrada, aprendizado e acesso.") encurta; o botão "Pesquisar na
  documentação"; "A busca inclui o conteúdo dos guias. Estes são guias do produto, separados da
  memória do projeto." no ⓘ; as descrições dos guias encurtadas para uma linha (a inteira no
  tooltip); o link "Markdown para agentes →" de cada cartão (fica "Ler Markdown" no guia aberto); a
  caixa final "Para agentes e integrações". Os títulos e descrições vêm em inglês da API: a fase B
  decide de onde sai o português.

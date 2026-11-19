# O painel do ai-memory 3.5.0, tela a tela

Inventário da fase A do plano 40 (`docs/plans/40-memory-panel.md`): o que cada tela do painel web
do upstream mostra, de onde vem cada dado e o que muda no Cadex. Feito em 2026-11-19 sobre o
painel rodando por `core/features/memory/server/examples/web_reference.rs` numa cópia dos dados do
dono, com os 15 prints (pt-BR, escuro) e o código no commit fixado (411d90d) do crate ai-memory-web.

Os nomes do upstream (rotas, modelos, funções, campos do JSON) vão sem crase: não são caminhos
deste repositório. "reader.x" é a função x do ReaderPool do ai-memory-store que a rota chama.
"Só no HTML" quer dizer que nenhuma rota de /api/v1 devolve o dado; "root" quer dizer que a rota
chama require_admin (no Cadex, dono único sem usuários no banco, a checagem passa).

A API JSON (/api/v1) tem: workspaces, projects, workspaces/{w}/overview,
.../projects/{p}/{pages, pages/{path}, history/{path}, recent, briefing, overview, handoffs,
sessions, sessions/{id}/observations, graph}, graph, search (GET e POST), docs, docs/{slug},
docs/features/status. Fora dela, o único JSON do painel é /web/inbox/notifications.

## A moldura (base.html)

**Barra da esquerda** (aside app-sidebar), de cima para baixo:
- Marca: logo (cérebro colorido) + "ai-memory" e, embaixo em laranja e caixa alta, "ESPAÇO DE
  TRABALHO DOS AGENTES". Leva a "." (Visão geral).
- ESPAÇO DE TRABALHO: Projetos (pasta) → "."; Caixa de entrada (envelope) → inbox, com um número
  de mensagens na fila ao lado e, embaixo, um painel com os projetos que têm mensagem (até 5,
  "projeto · n", e "ver todos os N projetos →"); Workstreams (galho) → workstreams; Pesquisar na
  memória (lupa) → search; Grafo de conhecimento (grafo) → graph.
- OBSERVAR E MELHORAR: Revisão de aprendizado (escudo) → pending; Saúde do servidor (servidor) →
  health.
- RECURSOS: Documentação (arquivo) → docs; Histórico de alterações (relógio) → docs/changelog.
- Pé fixo: ícone de chip + "Contexto que permanece." / "Entre agentes. Entre sessões."
- Item atual: fundo mais claro e filete laranja à esquerda. Projetos fica aceso em toda rota /w/...
- O número e o painel da Caixa de entrada vêm de /web/inbox/notifications (JSON: pending,
  project_count, projects[{workspace, project, pending}] até 5), consultado a cada 10 s
  (_inbox_notifications.html; reader.pending_inbox_counts). Sem mensagens, os dois somem.

**Cabeçalho** (header app-topbar): legenda fixa "Espaço de trabalho / **Operações dos agentes**";
campo "Pesquisar na memória..." (vai a search?q=); nas telas de um projeto vira "Pesquisar em
default/cadex" (_header_search_scoped.html, manda workspace e project); no grafo geral,
"Pesquisar...". Depois, botão Sair (só aparece com cookie de sessão do navegador; não aparece nos
prints), seletor de idioma (English / Português (Brasil), por cookie) e o trio Claro / Escuro /
Sistema (_theme.html). Embaixo do cabeçalho, um filete em degradê verde-lilás.

**Rodapé**: "ai-memory · Memória do projeto e operações dos agentes" à esquerda, "v3.5.0" à direita.

**No Cadex**: a barra vira as seções da página Memória no pé da barra lateral (os três grupos e os
nove itens, com o contador da caixa de entrada); a marca e o pé "Contexto que permanece" caem ou
viram o título da página; a busca do cabeçalho fica no topo da página Memória (e no ⌘K); Sair,
idioma e tema caem (seguem o Cadex); a legenda "Operações dos agentes" e o rodapé com a versão
podem virar uma linha discreta ("ai-memory 3.5.0") ou cair.

## 1. Visão geral — "Painel de memória" (print 01)

Rota /web/ (index::handler), modelo projects.html.

- Sobretítulo "VISÃO GERAL DO ESPAÇO DE TRABALHO", título "Painel de memória", linha "Acompanhe a
  atividade, investigue o uso de tokens e coordene seus agentes." Botão laranja "Abrir caixa de
  entrada" → inbox.
- Cinco cartões-número, cada um com ícone e um link: Projetos 5 "Visíveis no seu espaço de
  trabalho" (→ #project-list); Sessões 201 "Projetos com mais sessões primeiro" (→ ?sort=sessions);
  Eventos capturados 86023 (?sort=events); Páginas compiladas 196 (?sort=pages); Sessões abertas 0
  em laranja (?sort=open&state=open).
- Nota: "Última captura: há 9 horas. Aberta significa que nenhum SessionEnd foi recebido; ..." (a
  primeira last_activity da lista).
- Só para root e com métricas ligadas: bloco "Saúde da captura dos hooks" (aceitos, descartados
  pela política, descartados por capacidade, limitados por taxa). Não aparece no print.
- Aviso âmbar se há mensagens na fila: "N mensagens aguardando agentes em proj (n), ..." (até 5).
- Só quando existe o recibo da migração OKF: diálogo "Sua memória foi atualizada para o formato
  2.0". Não aparece.
- "Seus projetos" + contador; filtro de texto "Filtrar projetos..." e seletor Todos os projetos /
  Com sessões abertas / Com mensagens na fila (os dois filtram no navegador, com "N de M" e estado
  vazio "Nenhum projeto corresponde a estes filtros").
- Cartões em grade de 3: ícone de pasta, workspace em mono ("default"), nome do projeto (link →
  /w/{w}/{p}), selo "N caixa de entrada" se há fila; linha dos agentes ("Claude Code" ou "Nenhuma
  sessão de agente ainda"); quatro números (Sessões, Eventos capturados, Páginas compiladas "49
  páginas", Sessões abertas); pé "Última captura: há 9 horas" (ou "Nenhuma captura ainda") e
  "Explorar agentes ↗" → /w/{w}/{p}?tab=agents.
- Vazio: "Seu espaço de trabalho começa aqui". Fim da página: dobra "Sobre a memória compilada".

Dados:
- Números e cartões: /api/v1/projects dá workspace_name, project_name, page_count, session_count,
  observation_count, open_session_count, last_updated, last_activity (somas feitas no cliente,
  como o handler faz). Confere com o print: 44+32+125 = 201 sessões, 196 páginas.
- Linha dos agentes por projeto (reader.registered_agents, agent_label): só no HTML.
- Fila por projeto (reader.pending_inbox_counts): só no HTML (o JSON das notificações traz só os 5
  maiores).
- Saúde da captura: só no HTML, root, state.ingest_metrics.
- Ordenação (?sort=): feita no handler sobre a lista; no Cadex, no cliente.

No Cadex: cada cartão ganha "Abrir no Cadex" (o projeto do Cadex com a mesma pasta); o diálogo OKF
cai.

## 2. Caixa de entrada — "Caixa de entrada dos agentes" (print 02)

Rota /web/inbox?workspace=&project=&box=inbox|outbox&state=&offset= (inbox::handler), modelo
inbox.html. Envio e edição: POST /web/messages, /web/messages/{id}/edit, /save, /release.

- Trilha "Projetos / default / cadex / Caixa de entrada"; sobretítulo "MANTENHA O TRABALHO EM
  ANDAMENTO"; título; "Caixa de mensagens: **default / cadex**" (link ao projeto); botão "+ Nova
  mensagem" (→ #compose).
- Aviso "Caixa indisponível" se a leitura falhou.
- Cartão "Aguardando agentes": "N na fila · M projetos" e um link por projeto com fila, ou
  "Nenhuma mensagem aguardando agentes nos projetos aos quais você tem acesso."
- Coluna esquerda, "CAIXA DE MENSAGENS DO PROJETO": seletor do projeto (com "· n" na fila), abas
  Recebidas / Enviadas, "Estado da mensagem" (Todas as mensagens, Aguardando coleta, Coletadas,
  Canceladas, Em edição; muda ao escolher). Aviso de mensagens retidas em edição. Linhas
  expansíveis: envelope, assunto, "origem → destino", "agente · quando", selo do estado; abertas
  mostram o id, o corpo, a nota de "coletada não quer dizer feita" e, se pendente, Editar (ou
  Continuar editando / Descartar alterações). A edição abre assunto e corpo no lugar. Paginação
  Mais novas / Mais antigas. Vazio: "Um pouco de tranquilidade" + duas linhas.
- Coluna direita, "DIRETO PARA UM AGENTE / Nova mensagem": Do projeto, Para o projeto (com dica),
  Para o agente (só os registrados no destino; desabilitado sem nenhum), campo de token de escrita
  quando o login só lê, Assunto (opcional, 200), Mensagem (8000, contador "0 / 8,000", "Texto
  simples · segredos são removidos"), nota "Na fila para a próxima verificação ... não inicia um
  agente", botão "Colocar mensagem na fila ↗" e a linha de resultado (com "Ver enviadas").

Dados: tudo só no HTML. Lista: reader.message_history_filtered e message_in_mailbox; projetos e
filas: list_projects_with_stats, pending_inbox_counts; destinatários: registered_agents; envio e
edição: inbox::send, begin_edit, save_edit, release_edit (exigem escrita no projeto e CSRF).

No Cadex: o token de escrita e o CSRF caem (o app fala pelo socket); "Para o agente" pode
mostrar as contas do Claude Code do dono.

## 3. Workstreams — "Workstreams gerenciados" (print 03)

Rota /web/workstreams?page= (workstreams::handler), modelo workstreams.html. Root.

- Título, "Estado operacional entre projetos, ordenado por necessidade de atenção e atividade
  recente.", "Página 1" à direita.
- Tabela: Workstream (nome; "default/bkdg-center" link ao projeto + id curto em mono), Estado
  (selo verde ativo, âmbar interrompido, neutro nos outros), Execução mais recente (selo do
  agente + id curto da execução, "Início há 1 dia[, fim ...]" ou "Não iniciado"), Evidências ("0
  evento" + selos dos harnesses ligados), Atividade (relativa, à direita).
- Paginação Anterior / Próxima. Vazio: "Nenhum workstream gerenciado nesta página."

Dados: só no HTML, reader.operational_workstreams(PAGE_SIZE+1, offset), workstream_row.

## 4. Pesquisar na memória (print 04)

Rota /web/search?q=&scope=&kind=&tier=&explain=1 (search::handler), modelo search.html.

- Trilha "início / [projeto /] pesquisa"; título "Pesquisar: **memória**" (o termo em verde); num
  projeto, selo "em default/cadex ×" que volta à busca geral.
- Barra: seletor de escopo (Todos os projetos, depois os projetos por workspace), Qualquer tipo
  (kind), Qualquer camada (tier), o termo, "Explicar classificação" e o botão Pesquisar.
- Com "explicar": caixa "Rastro da recuperação" (no projeto: streams ativos, embedder,
  reclassificador; geral: nota de FTS entre projetos; tempos por stream em ms), e por resultado
  posição, rank, fused, authority, tabela stream/rank/raw/rrf, entidades e "alcançado por".
- "34 resultados" (ou "primeiros N resultados"); vazio: "Nenhum resultado para X [com estes
  filtros]" + "Pesquisar em todos os projetos"; sem termo: as páginas recentes.
- Cada resultado: título em verde (→ a página), trecho com o termo marcado, "workspace/projeto ·
  caminho".

Dados: /api/v1/search?q=&limit=(1–100)&scope=w/p (ou workspace+project) dá workspace, project,
path, title, kind, snippet (já com <mark>), rank; geral é FTS (reader.search_pages), com escopo é
o híbrido (recall::search_scopes). Testado: os mesmos 34 resultados. Faltam na API: os filtros
kind e tier (o HTML usa reader.search_pages_with_meta com PageFilter), o rastro do "explicar"
(recall.rs, active_streams, hybrid_search_scopes) e as recentes sem termo
(recent_pages_global / recent_pages_for_project). Opções de escopo: /api/v1/projects.

## 5. Grafo de conhecimento — "Grafo de links" (print 05) e o do projeto (print 14)

Rotas /web/graph (graph::global_handler) e /web/w/{w}/{p}/graph (graph::project_handler), modelo
graph.html.

- Geral: trilha "início / grafo", título "Grafo de links", "Wikilinks resolvidos cujas
  extremidades estão em projetos diferentes...". Nos dados do dono: "Ainda não há links entre
  projetos." e, em "Conexões", "Nenhum link resolvido para listar."
- Projeto: trilha "início / default / cadex / grafo", "Grafo de links de default/cadex", "Páginas
  mais recentes deste projeto e os wikilinks resolvidos entre elas."; aviso âmbar se cortado no
  teto de nós; um SVG 800×800 com os nós num círculo (circular_layout, raio fixo), cada nó um
  círculo verde com o título cortado e link à página, arestas como linhas; depois a tabela
  "Conexões" De / Para.
- Nos dados do dono o grafo do cadex tem 49 nós e 0 arestas: um anel de títulos sobrepostos, quase
  todos de sessões.

Dados: /api/v1/graph dá edges (entre projetos); /api/v1/.../graph dá workspace, project,
truncated, nodes[{path, title, degree}], edges. Cobre tudo; o desenho fica com o Cadex.

## 6. Revisão de aprendizado — "Gravações pendentes" (print 06)

Rota /web/pending?project=&sort= (pending::handler), modelo pending.html. Root.

- Título, "Propostas de melhoria automática que aguardam uma decisão...".
- Filtro: Projeto ("Todos os projetos (0)" e um por escopo com contagem), Ordenação (Projeto e
  depois data de envio; Confiança, menor primeiro; Confiança, maior primeiro; Envio, mais recente
  primeiro), botão Aplicar.
- "0 exibidas · 0 pendentes em 0 projeto" (corte em 500, com dica da CLI); vazio "Nenhuma
  proposta pendente."
- Cada proposta (dobrável): título, selo da operação (âmbar se reescreve página), selo "regra" se
  _rules/, kind; escopo, caminho, "confiança N%", "enviada há X". Aberta: avisos de regra e de
  reescrita (link à página atual), Justificativa, Corpo proposto, id, e Aprovar / Rejeitar + motivo
  (ou, com token só de leitura, os comandos POSIX e PowerShell).

Dados: só no HTML, reader.list_pending_auto_improve_scopes e list_pending_auto_improve_reviews.
Aprovar e rejeitar vão a /admin/pending-writes/{id}/approve|reject, do servidor do upstream, fora
do crate web.

No Cadex: a ação pede rota nossa no engine; os comandos de CLI caem.

## 7. Saúde do servidor (print 07)

Rota /web/health (health::handler), modelo health.html. Root.

- Título, "Contadores, filas e estado dos modelos deste processo do servidor. Somente leitura: cada
  correção é um comando a executar, não um botão."
- Aviso âmbar quando os contadores do processo não foram ligados ao painel (é o caso no exemplo:
  "os dados de hooks, spool e provedores abaixo estão vazios").
- Verificações: "Todas as verificações do servidor passaram." ou a lista (erro em rosa, aviso em
  âmbar, com "Correção: comando").
- Seções em pares rótulo / valor mono: Hooks (aceitos, rejeitados 429, resultados, descartados,
  última gravação); Gravação, spool e recuperação (fila de gravação, spool de hooks, registro de
  recuperação); Consolidação (última conclusão, fila, pendente mais antigo); Embeddings e modelos
  (gerador, provedor de embeddings, provedor LLM, reclassificador, vetores, identidade
  armazenada); Índice e armazenamento (fts, banco de dados em bytes e recuperáveis).

Dados: só no HTML. reader.derived_index_status(_for_embedding), storage_status,
session_consolidation_queue; state.health (ingest, providers, process) e state.recall;
health::checks / localized_checks; routes/health.rs::sections.

No Cadex: hooks, spool e provedores são do servidor do upstream; o engine do Cadex captura de
outro jeito, então essas linhas mostram os contadores do próprio engine ou caem.

## 8. Documentação (print 08) e Histórico de alterações (sem print)

Rotas /web/docs?q= (documentation::index), /web/docs/{slug} e /web/docs/{slug}.md
(documentation::page), modelos documentation_index.html e documentation_page.html. O Histórico de
alterações é /web/docs/changelog.

- Índice: sobretítulo "APRENDER E CONFIGURAR", "Documentação", botão "Histórico de alterações ↗";
  destaque "Incluída na versão 3.5.0 / Comece pelo guia de ativação" com "Explorar recursos →"
  (docs/features); busca "Buscar recurso, comando ou chave de configuração..." + "Pesquisar na
  documentação"; "28 guias. A busca inclui o conteúdo dos guias..."; cartões em grade de 3
  (categoria em laranja: Comece aqui, Fluxos de agentes, Aprendizado e recuperação, Acesso e
  integração, Operações; título ↗; descrição; "Markdown para agentes →"); caixa final "Para agentes
  e integrações".
- Página de um guia (sem print): trilha, categoria · versão, título, "Ler Markdown"; no guia
  features, "Estado efetivo da instalação" (um cartão por recurso: estado, detalhe, próximo passo,
  guia); barra de guias à esquerda, "Nesta página" à direita, o Markdown renderizado e a fonte.
- Histórico de alterações: o mesmo modelo, com o seletor de versão (Unreleased, 3.5.0, 3.4.7, ...,
  31 entradas). Abre em Unreleased, que hoje está quase vazio.

Dados: /api/v1/docs?q= dá version e documents[{id, title, description, category, source}];
/api/v1/docs/{slug}?release= dá document, markdown, release, releases; /api/v1/docs/features/status
dá features[{id, title, state, detail, next_step, guide}]. Cobre tudo, mas em inglês: os títulos em
português vêm do catálogo de tradução (i18n.label) e a API usa Language::English.

No Cadex: o Markdown renderiza pela feature markdown; os links "↗" abrem o guia dentro da página.

## 9. Projeto — "cadex" (print 09, aba Visão geral)

Rota /web/w/{w}/{p}?tab=overview|agents|tokens|sessions|knowledge (project::handler), modelo
project.html com _agent_cards.html, _usage_panel.html, _project_tabs_script.html (abas no cliente,
a aba pela query) e _dashboard_refresh.html (recarrega números, agentes e tokens a cada 10 s).

Comum: trilha "Projetos / default / cadex"; sobretítulo "ESPAÇO DE TRABALHO DO PROJETO"; título;
"Entenda seus agentes, examine suas sessões e encontre chamadas de alto consumo."; botão "Enviar
mensagem a um agente" (→ inbox#compose); abas Visão geral, Agentes, Uso de tokens, Sessões,
Conhecimento; à direita "Caixa de entrada ↗" e "Grafo de links ↗".

**Visão geral** (no print): "VISÃO GERAL / Visão geral do projeto"; cinco cartões-link: Sessões 44
"Atividade registrada", Eventos capturados 15098 "Sessões mais movimentadas primeiro", Páginas
compiladas 49 "Conhecimento para consulta", Sessões abertas 0 (laranja) "Somente sessões não
encerradas", Tokens (entrada / saída) "—" "Totais de sessões informados"; nota "Última captura: há
9 horas. Nenhuma sessão aberta registrada no momento."; "Agentes:" com selos lilás "Claude Code ·
44"; cartão "Caixa de mensagens" com "Abrir caixa de entrada ↗" e a lista das pendentes (assunto,
"de projeto", natureza, trecho, quando; cortada, com o comando da CLI) ou "Nenhuma mensagem
pendente para este projeto."

**Agentes** (sem print; lido do HTML): "SUA FROTA DE AGENTES / Um projeto. Todos os agentes." e
"1 registrado"; um cartão por agente: avatar (Cl, Cx, Ai), nome (→ tela do agente), "44 sessões
registradas", selo "N abertas" ou "Nenhuma sessão aberta", Tokens informados, Chamadas medidas,
Cobertura de uso "0/44 sessões" com barra, aviso "Uso ainda não informado..." ou "entrada · saída ·
cache", e "Explorar sessões ↗" / "Mensagem ↗". Vazio: "Seus agentes aparecerão aqui".

**Uso de tokens** (sem print; o mesmo painel do print 12): seis números (Chamadas capturadas,
Entrada nova, Saída, Leitura do cache, Gravação no cache, Entrada do cache), filtros (busca, todas
as respostas / sinais de investigação, maior uso / mais recente, De e Até em UTC, Modelo, Cliente
de agente com 32 harnesses, ID da sessão, ID do turno, Ferramenta, Pesquisar), tabela das
respostas (resposta/sessão, modelo, entrada, saída, cache, total, sinal; detalhes do turno e das
ferramentas), "0–0 de 0 respostas ...", paginação, nota longa. Vazio: "Nenhum uso de resposta
informado ainda".

**Sessões** (sem print): "ATIVIDADE RECENTE / Sessões"; tabela Agente (selo-link → sessão),
Início, Duração, Eventos, Tokens. Filtros pela query: só abertas, ordenar por eventos.

**Conhecimento** (sem print): "MEMÓRIA COMPILADA / Conhecimento"; busca no projeto (→ search com
escopo); à esquerda "Páginas", a árvore por pasta ("_rules/ (2)", "decisions/ (1)", "gotchas/
(2)") com até N títulos e "Ver todas N", e dobrado "Sistema" (_lint/, sessions/ (43)); à direita
"Atividade recente": título, selo kind, selo lilás do agente, caminho, quando. Vazio com texto
diferente se há sessões ou não.

Dados:
- Cartões, menos tokens: /api/v1/projects (o item do projeto) ou .../briefing (counts.sessions,
  observations, pages_latest) com last_observation_at. Tokens (reader.total_session_usage): só
  no HTML.
- Selos por agente (reader.session_counts_by_agent): só no HTML.
- Caixa de mensagens (reader.list_inbox_with_senders, pending_message_count): só no HTML.
- Agentes (reader.agent_usage → operations::agent_card): só no HTML.
- Uso de tokens (reader.token_usage_report_page → operations::usage_panel, UsageQuery): só no
  HTML.
- Sessões: /api/v1/.../sessions?limit=(≤100)&offset=&include_open= dá session_id, cwd, agent_kind,
  started_at, ended_at, observation_count, actor_user, consolidation, usage. Falta o filtro "só
  abertas" e a ordem por eventos (o HTML usa sessions_for_scope_view).
- Conhecimento: /api/v1/.../pages (path, title, kind, tier, updated_at) dá a árvore (agrupar por
  pasta e separar as de sistema como project::to_folders e is_system_page); .../recent dá a
  atividade recente. O selo do agente por página (reader.latest_page_agent_kinds): só no HTML.
- O overview do projeto na API (handoff, briefing, health com órfãs e duplicadas) traz dados que o
  HTML não mostra nesta tela.

No Cadex: "Abrir no Cadex" ao lado do título; uma sessão leva também ao terminal dela quando
ainda existe.

## 10. Página — uma página da memória (print 10)

Rota /web/w/{w}/{p}/p/{path} (page::handler), modelo page.html com _knowledge.html.

- Trilha "início / default/cadex / caminho"; título; selos tier (verde, "semantic") e kind
  ("decision"), fixada e expirada quando for; "Atualização há 1 dia · Histórico · Criação há 1
  dia", "substitui caminho" e "editada por usuário (nome, e-mail)" quando há.
- Caixa "Evidências e validade do conhecimento" (aberta): "Versão id · As evidências se aplicam a
  esta versão indexada..."; Expiração; Fontes acessíveis ("0 citações registradas...") com a lista
  das fontes e paginação; Contradições declaradas (contagem e lista). Dobra "Por que esta página
  foi recuperada?" (consulta, "pesquisar com este contexto", recomputar, rastro).
- O Markdown renderizado.
- Coluna direita: "Nesta página" (sumário, se há títulos), "Citada por" ("Nenhuma página aponta
  para cá ainda." ou a lista com "e mais N"), "Cita".

Dados: /api/v1/.../pages/{path} dá id, workspace, project, path, title, kind, tier, pinned,
created_at, updated_at, supersedes, frontmatter, body_markdown, links, backlinks (com ETag). Só no
HTML: a caixa de evidências (knowledge::view, reader.page_provenance), o autor (page_meta.author),
o "expirada" e o sumário (markdown.rs). O "por que foi recuperada" depende da busca com explain.

No Cadex: o Markdown pela feature markdown; um link de página abre a página no mesmo painel.

## 11. Histórico da página (print 11)

Rota /web/w/{w}/{p}/h/{path}?from=&to=&limit=&offset= (history::handler), modelo history.html.

- Trilha "... / caminho / histórico"; "Histórico de caminho"; "1 versão, mais recentes primeiro.
  Versões substituídas permanecem no registro; nada aqui pode alterá-las."
- Diff: "Alterações de X para Y" ou "Conteúdo de 5ef7d2d8 (nenhuma versão anterior neste
  caminho)", os títulos, e o bloco mono com o cabeçalho do hunk e as linhas + (verde) e - (rosa);
  "mesmo corpo", "grande demais" e "cortado no limite" como textos.
- "Versões 1-1 de 1": tabela De (rádio), Para (rádio), Versão (id curto + selo "mais recente",
  "substituiu X"), Gravação, Autor ("—"), Título, Tamanho ("386 caracteres"), "vs. anterior";
  botão "Comparar selecionadas", "Versões mais novas / mais antigas".

Dados: /api/v1/.../history/{path}?from=&to=&limit= dá total, offset, limit, versions[{id,
supersedes, is_latest, title, tier, created_at, body_chars, autor quando há}] e diff{from, to,
status changed|same|too_large, reason, truncated, hunks[{old_start, old_len, new_start, new_len,
lines}]}. Cobre tudo.

## 12. Sessão — "Linha do tempo da sessão" (print 12)

Rota /web/w/{w}/{p}/s/{id}?at=&limit= (session::handler), modelo session.html com
_usage_panel.html.

- Trilha "início / default/cadex / sessão id..."; links "← Todas as sessões de claude-code"
  (→ tela do agente) e "Recuperações"; título; selo do agente, "iniciada ISO, encerrada ISO" (ou
  "ainda aberta"); "Observações capturadas, em ordem..." e quantas ficaram em outro projeto.
- O painel "Uso de tokens" da sessão (o mesmo do projeto; selo "Durante as sessões").
- Barra fixa: Primeira, Anterior, "1–50 de 882", Próxima, Última, "Ir para" com controle
  deslizante, número e "Ir"; j/k e setas andam uma observação.
- As observações: "#n", selo kind (session-start, user-prompt, other...), título, "há 23 horas",
  corpo em mono (cortado).

Dados: /api/v1/.../sessions/{id}/observations?offset=&limit=(≤200)&order=&body_max_chars= dá
session{session_id, cwd, agent_kind, started_at, ended_at, observation_count, usage, ...},
observations[{id, kind, title, body, importance, created_at, ...}], total, offset, limit, order,
elided_other_scope, body_max_chars. Cobre a linha do tempo; o painel de tokens da sessão
(token_usage_report_page): só no HTML.

No Cadex: "Abrir no Cadex" leva ao terminal onde a sessão roda, se ainda aberta, ou retoma a
conversa do Claude Code (o cwd e o id da sessão estão no JSON).

## 13. Agente — "Claude Code" (print 13)

Rota /web/w/{w}/{p}/agents/{agent}?offset= (agents::handler), modelo agent.html.

- Trilha "Projetos / cadex / Claude Code"; sobretítulo "INFORMAÇÕES DO AGENTE · default"; título;
  "Sessões, consumo e cobertura de captura de cadex."; botão "Enviar mensagem ao agente".
- Quatro cartões: Sessões registradas 44 "0 sem evento de encerramento"; Tokens informados "—"
  "Entrada + saída + cache"; Chamadas medidas 0; Cobertura de uso "0%" "0 de 44 sessões informam
  o uso".
- Faixa âmbar "Há uma lacuna de visibilidade" quando a cobertura é menor que 100%.
- "ATIVIDADE / Sessões": tabela Sessão (id curto, ou nome · id, ↗), Estado (Aberta / Encerrada),
  Início, Duração, Eventos, Tokens · entrada / saída. Paginação Mais novas / Mais antigas.

Dados: só no HTML, reader.agent_usage e agent_sessions, operations::agent_card e session_row.
A lista de sessões dá para tirar de /api/v1/.../sessions filtrando agent_kind, mas sem o nome nem a
paginação por agente.

## 14. Recuperações — "Histórico de recuperações" (print 15)

Rota /web/w/{w}/{p}/s/{id}/retrievals (retrievals::handler), modelo retrievals.html.

- Trilha "... / sessão id / Recuperações"; "‹ Linha do tempo da sessão"; título; "Cada
  memory_query que esta sessão executou ... O registro é opcional (retrieval.record_history)".
- Vazio nos dados do dono: "Nenhuma recuperação registrada para esta sessão."
- Com registros: paginação como a da sessão; cada um com selo do escopo, quando, a consulta em
  mono, resultados, limite, piso, duração em ms, streams, filtros, aviso, e a lista dos acertos
  (posição, caminho → página, @versão, relevância, "explicar" dobrável).

Dados: só no HTML, reader.retrieval_history_page e session_summary_scoped.

## Telas sem print

Aba Agentes, Uso de tokens, Sessões e Conhecimento do projeto, página de um guia e Histórico de
alterações: descritos pelo modelo e pelo HTML servido, sem print. Fora do escopo: login.html,
change_password.html, admin_required.html (recusa de root), not_found.html, namespace.html e a
pasta management (painel de contas, só com servidor de vários usuários).

## Cobertura da API e o que o engine do Cadex acrescenta

| tela | API /api/v1 | rota JSON nova no engine |
|---|---|---|
| moldura (contador da caixa) | nenhuma (há /web/inbox/notifications) | contagem da fila por projeto (pending_inbox_counts, todos os projetos) |
| 1. Visão geral | parcial (projects) | agentes por projeto (registered_agents) e fila por projeto; saúde da captura, se mantida |
| 2. Caixa de entrada | nenhuma | listar mensagens (message_history_filtered, por caixa e estado, paginado), destinatários (registered_agents), enviar, começar/salvar/soltar edição |
| 3. Workstreams | nenhuma | operational_workstreams paginado |
| 4. Pesquisar | parcial (search) | filtros kind e tier, explain com o rastro, recentes sem termo |
| 5. Grafo geral e do projeto | total (graph) | nenhuma |
| 6. Revisão de aprendizado | nenhuma | escopos e propostas pendentes (list_pending_auto_improve_*), aprovar e rejeitar |
| 7. Saúde do servidor | nenhuma | o snapshot de saúde (índice, armazenamento, consolidação, modelos, checks) |
| 8. Documentação e changelog | total (docs), só em inglês | nenhuma (traduzir no app ou servir o texto pt-BR) |
| 9. Projeto: Visão geral | parcial (projects, briefing) | total de tokens, sessões por agente, caixa do projeto |
| 9. Projeto: Agentes | nenhuma | agent_usage (o cartão do agente) |
| 9. Projeto: Uso de tokens | nenhuma | token_usage_report_page com os filtros de UsageQuery |
| 9. Projeto: Sessões | parcial (sessions) | só abertas e ordem por eventos (sessions_for_scope_view) |
| 9. Projeto: Conhecimento | parcial (pages, recent) | agente por página (latest_page_agent_kinds) |
| 10. Página | parcial (pages/{path}) | evidências (knowledge::view, page_provenance), autor, expirada |
| 11. Histórico | total (history) | nenhuma |
| 12. Sessão | parcial (observations) | uso de tokens da sessão (token_usage_report_page por sessão) |
| 13. Agente | nenhuma | agent_usage + agent_sessions paginado |
| 14. Recuperações | nenhuma | retrieval_history_page |

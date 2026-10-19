# Plano 6 — Git: source control e grafo

Depende de: planos 4 e 5 · Features: source-control, git-history (núcleo e app) · Specs a escrever:
source-control, git-history.

## O que eu quero
- **Source control** no painel lateral: branch atual (inclusive HEAD destacado), upstream e quantos
  commits à frente/atrás; lista de alterados separando staged e não staged, com o tipo da mudança;
  stage e unstage por arquivo e de tudo; descartar com confirmação; mensagem e commit (⌘Enter);
  fetch, pull só fast-forward, push quando há upstream; trocar de branch; atualiza sozinho quando o
  repositório muda.
- **Diff:** clicar num arquivo abre o diff numa aba, lado a lado ou unificado, com destaque de sintaxe
  (visualizador de código do plano 5); binário e arquivo enorme avisam.
- **Explorer** marca arquivos alterados com a cor do tipo de mudança.
- **Histórico (git graph):** aba com o log paginado e o grafo de branches e merges desenhado em
  faixas; busca e filtro de commits; arquivos de cada commit e o diff de cada um; abrir o commit no
  remoto (GitHub, GitLab, Bitbucket).

## O que eu não quero
- Reimplementar o git: tudo passa pelo binário `git` do usuário, com saída em formato estável
  (porcelain v2, `-z`) e tempo limite em cada comando.
- Ação destrutiva sem confirmação (descartar, push com divergência).
- Carregar o histórico inteiro de uma vez ou travar a interface num repositório grande.
- Comando git fora do workspace autorizado (plano 4).

## Como eu quero
**Onde estamos.** O núcleo sabe rodar processos com tempo limite e saída limitada? Ainda não: o
terminal usa PTY (`core/features/terminal/pty.zig`). Criar em core/shared um executor de processo
(argumentos sem shell, cwd, tempo limite, limite de saída, ambiente controlado) quando a segunda
feature precisar (aqui: source-control e git-history). Manifestos: `core/features/source-control/CLAUDE.md`,
`core/features/git-history/CLAUDE.md`, `apps/macos/features/source-control/CLAUDE.md`,
`apps/macos/features/git-history/CLAUDE.md`.

**Fases:**
- **A. Executor de processo e repositório (núcleo):** achar a raiz do repositório a partir de uma
  pasta, checar se o git existe (mensagem clara se não), status em porcelain v2 com -z (parser
  testado com nomes com espaço, acento, renomeação), observação do .git para atualizar.
- **B. Ações (núcleo):** stage, unstage, descartar (arquivo novo vai para a Lixeira pelo app),
  commit, fetch, pull --ff-only, push, listar e trocar branches; diff de um arquivo (conteúdo
  original e alterado para o lado a lado, mais o patch).
- **C. Painel (app):** lista com staged/não staged, botões e menu com comandos registrados, campo de
  mensagem, estados (sem repositório, git ausente, carregando, erro), marcação no explorer.
- **D. Diff (app):** aba com dois visualizadores sincronizados ou um unificado, marcações de linha
  adicionada/removida, destaque pelo tree-sitter.
- **E. Histórico:** log paginado (sha, autor, data, pais, assunto, estatísticas); algoritmo de faixas
  do grafo puro e testado no núcleo; aba com lista virtualizada, busca, detalhes do commit, diff por
  arquivo, URL do commit no remoto a partir do `origin`.

## Como validar
- `make check` passa ao fim de cada fase.
- Testes do núcleo com repositórios temporários (git init no teste): status com renomeação e nomes
  com espaço; stage, commit e diff; pull fast-forward recusado quando diverge; faixas do grafo
  corretas para um histórico com dois merges; URL do remoto para SSH e HTTPS.
- Manual, com print: no próprio repositório do Cadex, alterar um arquivo, ver no painel e no
  explorer, abrir o diff, fazer stage e commit, ver o commit no grafo, abrir no GitHub.
- Atualizar specs, `CLAUDE.md` das features e o status em `docs/plans/README.md`.

## Fechamento (2026-10-19)
Fases A a E feitas: A e B num commit (núcleo), C e D noutro (painel e diff), E no último (histórico).
O executor de processo ficou em `core/shared/process.zig`; o git roda pela porta de entrada da
source-control, que a git-history usa. Conferido no app em segundo plano (menus, sem teclas): painel
num repositório temporário com M e ?, um commit feito no terminal sumindo da lista sozinho, PATH sem
git mostrando a mensagem de instalar, marcas no explorer, diff lado a lado com as cores do editor,
o histórico do próprio Cadex (49 commits, etiquetas main e origin/main) e um repositório com dois
merges desenhado igual ao `git log --graph`, com os detalhes do merge (pais e arquivo +1 −0). Falta
conferir à mão, com o app na frente: ⌘Enter na mensagem, os botões + e − nas linhas, clicar num
arquivo do commit abrindo o diff, "Abrir no remoto" no GitHub (o teste confere a URL, não o
navegador) e o push de verdade. Ficou para depois do MVP: arrastar a divisa entre a lista e os
detalhes do histórico, e busca que ignore acento.

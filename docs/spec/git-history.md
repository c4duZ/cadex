# git-history

## Para que serve
Ver o histórico do repositório como um grafo: o que os agentes commitaram, de que branch veio cada
coisa, e abrir qualquer commit, seus arquivos e diffs.

## Comportamento
- Comando "Abrir o histórico do git" (⇧⌘H) abre, ao lado ou em nova aba pela configuração "Abrir
  arquivos" ("Abrir o histórico do git em nova aba" escolhe a aba na hora), um documento com a lista de commits, do mais novo para o mais
  antigo, de todas as branches.
- Cada linha: o grafo à esquerda (faixas coloridas, um ponto no commit, linhas para os pais, curvas
  nos merges e nas bifurcações), o assunto, as etiquetas (branches, tags, HEAD), o autor, a data
  relativa ("há 3 horas") e o sha curto.
- O histórico chega em páginas de 500 commits; rolar até o fim busca a próxima página. O grafo
  continua sem emenda entre páginas.
- Campo de busca no topo filtra por assunto, autor ou sha (no que já foi carregado e, ao apertar
  Enter, no repositório inteiro pelo git). Filtro "só a branch atual".
- Selecionar um commit mostra, embaixo, a mensagem inteira, autor, data, pais e a lista de arquivos
  com o tipo da mudança e +/− linhas. Clicar num arquivo abre o diff daquele arquivo naquele commit
  (aba de diff do source-control).
- "Abrir no remoto" abre o commit no navegador, a partir do `origin`: GitHub, GitLab, Bitbucket e
  Gitea (`https://host/dono/repo/commit/<sha>`), com remoto em SSH ou HTTPS. Sem remoto conhecido, o
  comando fica indisponível.
- "Copiar sha" copia o sha inteiro. Os dois ficam no menu de contexto da linha e na paleta.
- A aba atualiza quando o repositório muda (commit novo aparece no topo).

## Estados
- **Sem repositório / git ausente:** as mesmas mensagens do source-control.
- **Carregando:** a primeira página com indicador.
- **Vazio:** "Nenhum commit ainda".

## Casos de borda
- Repositório com 100 000 commits -> abre a primeira página na hora; nada trava.
- Merge octopus (três pais) -> desenhado com uma faixa por pai.
- Commit sem pai (raiz) e histórias separadas -> faixas que começam do nada.
- Assunto com emoji ou acento -> mostrado como está.

## Critérios de aceite
- [x] O log paginado traz sha, pais, autor, data, assunto e etiquetas.
- [x] As faixas do grafo saem certas para um histórico com dois merges.
- [x] URL do commit no remoto para SSH e HTTPS (GitHub, GitLab, Bitbucket).
- [x] Arquivos de um commit com o tipo e +/−.
- [x] O commit feito no painel aparece no topo do grafo.

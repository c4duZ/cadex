# git-history (núcleo)

## O que eu quero
- Log de commits paginado, arquivos de cada commit e diff de um arquivo num commit.
- Dados para desenhar o grafo (pais de cada commit e as faixas de cada linha).
- URL do commit no remoto (GitHub, GitLab etc.).

## O que eu não quero
- Carregar o histórico inteiro de uma vez (só a busca lê o log todo, e filtra aqui).
- Argumento vindo do app que o git leia como opção: sha só em hexadecimal.

## Como eu quero
- Porta de entrada: `history.zig`. Roda o git pela porta de entrada da source-control
  (`core/features/source-control/source_control.zig`, o mesmo tempo limite e ambiente).
- `log.zig`: `Log` guarda onde a página parou e as faixas; páginas de 500 com --date-order (filhos
  antes dos pais) de branches, tags, remotos e HEAD (o stash fica de fora), ou só do HEAD. Com busca,
  filtra assunto, autor ou começo do sha sem grafo. Repositório sem commits: página vazia.
- `graph.zig`: o algoritmo de faixas, puro: cada faixa espera um commit, as que esperam o mesmo se
  encontram no ponto dele, o primeiro pai continua a faixa, os outros pais vão para a faixa que já os
  espera ou para uma livre. Cada linha diz os segmentos da metade de cima e da de baixo.
- `details.zig`: mensagem inteira, pais e arquivos (name-status e numstat com -z, juntos), merge
  comparado com o primeiro pai. `remote.zig`: URL do commit a partir do origin, SSH ou HTTPS.
- O diff de um arquivo num commit é o commitSides do `core/features/source-control/diff.zig`, para o app ter uma aba
  de diff só.
- API C em `c_api.zig` (`cadex_history_*`).
- Spec: `docs/spec/git-history.md`. Status: pronto (plano 6, fase E).

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- `graph_test.zig`: faixas de dois merges, octopus, histórias sem raiz comum, páginas seguidas.
- `history_test.zig` com repositório temporário de dois merges: páginas, pais, etiquetas, busca, só a
  branch atual, arquivos de um merge, diff num commit e URL do remoto.

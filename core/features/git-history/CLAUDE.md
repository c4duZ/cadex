# git-history (núcleo)

## O que eu quero
- Log de commits paginado, arquivos de cada commit e diff de um arquivo num commit.
- Dados para desenhar o grafo (pais de cada commit).
- URL do commit no remoto (GitHub, GitLab etc.).

## O que eu não quero
- Carregar o histórico inteiro de uma vez.

## Como eu quero
- Mesmo acesso ao git da feature source-control, pela porta de entrada dela ou por core/shared.
- Spec de comportamento em docs/spec/git-history.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- Teste com repositório temporário com merge, conferindo os pais.

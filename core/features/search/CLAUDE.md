# search (núcleo)

## O que eu quero
- Busca de arquivos por nome, fuzzy, rápida o bastante para cada tecla digitada.
- Busca de conteúdo (texto e regex) com o resultado chegando aos poucos.
- Respeitar .gitignore, .ignore e arquivos ocultos conforme a preferência.

## O que eu não quero
- Busca que trava o app ou não pode ser cancelada.
- Uma busca nova competindo com a anterior: a anterior é cancelada.

## Como eu quero
- Índice de nomes em memória, atualizado pela observação de arquivos.
- Limite de resultados e de tamanho de arquivo lido.
- Spec de comportamento em docs/spec/search.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- Teste com uma árvore de exemplo que confere .gitignore e cancelamento.

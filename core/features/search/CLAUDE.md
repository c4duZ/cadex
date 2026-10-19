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
- Porta de entrada: `search.zig`. `fuzzy.zig` pontua um texto (letras em ordem; caixa e acentos do
  português não importam; começo de palavra vale mais) e `rank.zig` ordena uma lista. API C em
  `c_api.zig` (`cadex_fuzzy_rank`), usada hoje pela paleta de comandos.
- Spec de comportamento em docs/spec/search.md, escrita antes do código da busca de arquivos.
  Status: fuzzy pronto (spec da paleta); busca de arquivos e conteúdo no plano 4.

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- Teste com uma árvore de exemplo que confere .gitignore e cancelamento.
- `fuzzy.zig` e `rank.zig` testam a ordem ("na" põe "Nova aba" na frente), acentos e posições.

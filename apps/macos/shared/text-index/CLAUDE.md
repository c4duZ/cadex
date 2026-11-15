# text-index (app macOS)

## O que eu quero
- Busca em texto guardada em disco para quem precisa achar palavras em muito texto: o histórico de
  sessões dos agentes (plano 18, fase D) e, depois, a memória (plano 22).

## O que eu não quero
- Dependência nova: é o SQLite do sistema, com FTS5 (3.54 no macOS de 2026-11-14), pela
  `libsqlite3` que o macOS já traz (ADR 0007).
- Regra de feature aqui: o que se indexa e como se lê é de quem usa.

## Como eu quero
- `TextIndex.swift`: um arquivo SQLite por dono. Por id, um registro (JSON do dono), pedaços de
  texto para buscar (linhas FTS5: um documento que cresce ganha pedaços, nunca é reescrito) e uma
  tabela livre para a contabilidade do dono (os offsets de leitura). `search` acha os ids com todas
  as palavras como prefixo, sem acento nem caixa; a entrada vira só palavras. `batch` junta muitas
  mudanças numa escrita. Uma fila só usa cada índice.

## Como validar
- `make macos-test` (TextIndexTests): registros, textos, meta, busca por prefixo e sem acento,
  entrada estranha, arquivo que guarda e lote que falha sem deixar nada.

# 0006 — Editor: lê código, edita Markdown

Data: 2026-10-19 · Status: aceita

## Contexto
O código é escrito pelos agentes, numa aba de terminal. Ninguém vai programar na mão no Cadex. O
arquivo editado à mão é o Markdown: specs, `CLAUDE.md`, ADRs, notas. Um editor de código completo
(language servers, autocomplete, vim, formatar ao salvar) seria o maior risco técnico do projeto
(ADR 0001) e não seria usado.

## Decisão
- O editor é o NSTextView da Apple (TextKit 2). Digitação, desfazer, busca, acentos e acessibilidade
  vêm do sistema, sem biblioteca de editor.
- Para qualquer linguagem: números de linha, setinha de dobrar, destaque de sintaxe e linha atual
  destacada. Nada além disso.
- O destaque de sintaxe e as regiões de dobra vêm do tree-sitter (MIT, em C), que roda no núcleo
  Zig, na feature `editor`.
- Para Markdown, além disso:
  - autocomplete de caminhos ao digitar `](`, de títulos depois de `#` e de links estilo wiki `[[`;
  - ⌘+clique num link abre o arquivo no título certo;
  - link quebrado sublinhado;
  - "quem aponta pra cá": os arquivos que linkam o arquivo atual.
- Isso vem de um índice de títulos e links mantido pela feature `markdown` do núcleo, atualizado
  pela observação de arquivos. Não há language server.

## Consequências
- Sem processos externos de language server: menos memória, nada para instalar.
- O Windows reaproveita o tree-sitter e o índice de Markdown, que estão no núcleo.
- Não propor language server, autocomplete de código, vim ou formatar ao salvar: foram descartados
  de propósito. Se a necessidade mudar, este ADR é revisto.

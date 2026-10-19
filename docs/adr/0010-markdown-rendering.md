# 0010 — Markdown renderizado: md4c no núcleo, HTML numa WKWebView sem script

Data: 2026-10-19 · Status: aceita

## Contexto
O Markdown renderizado (`docs/spec/markdown.md`) precisa de tabelas, listas de tarefa, blocos de
código com destaque, imagens locais e links entre notas, no estilo do GitHub. O plano 5 propôs o
cmark-gfm (C, BSD) gerando HTML sanitizado numa WKWebView sem JavaScript; a alternativa nativa
(NSAttributedString) perde tabelas e blocos de código. ADR 0001 proíbe WebView para a interface,
com a exceção do preview web.

## Decisão
- O parser é o **md4c** (C, MIT, dois arquivos, sem passo de geração), compilado pelo Zig no núcleo.
  O cmark-gfm pede arquivos gerados pelo CMake (config e export), o que traz um passo de build a
  mais sem ganho para o que a spec pede: o md4c já tem tabelas, tarefas, tachado, autolinks e
  `[[wiki]]`.
- O HTML é gerado pelo próprio núcleo a partir dos eventos do md4c (feature `markdown`): âncoras de
  título no formato do GitHub, blocos de código coloridos pelo tree-sitter da feature editor, links
  para outras notas marcados para o app abrir no Cadex, e HTML embutido limpo (sem `script`,
  `style`, `iframe`, `object`, `embed`, `form`, `link`, `meta`, `base`, atributos `on*` e URLs
  `javascript:`).
- O app mostra esse HTML numa WKWebView com JavaScript desligado e uma Content-Security-Policy que só
  permite imagens locais e estilo embutido: mesmo um script que passasse da limpeza não roda. É a
  segunda exceção ao ADR 0001: só leitura de conteúdo, nunca interface do app.
- Títulos e links para o índice (autocomplete, links quebrados, "quem aponta pra cá") vêm do
  tree-sitter de Markdown, que dá as posições no texto; o md4c não dá.

## Consequências
- Dois parsers de Markdown no núcleo: md4c para desenhar, tree-sitter para posições. Um caso raro
  pode diferir entre eles (um link que um vê e o outro não); a spec de comportamento manda.
- O md4c entra no `NOTICE`.
- Se a WKWebView pesar na memória para notas pequenas, a alternativa nativa volta a ser avaliada.

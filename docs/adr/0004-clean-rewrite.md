# 0004 — Reescrita do zero, a partir do comportamento

Data: 2026-10-19 · Status: aceita

## Contexto
O Cadex é MIT, com código próprio. Código traduzido ou portado de outro app seria obra derivada e
continuaria sob a licença dele.

## Decisão
- Nenhum código de outro app é copiado, traduzido ou consultado durante a implementação. Isso vale
  para pessoas e para agentes.
- A referência é o comportamento: o que o usuário vê e faz no app, descrito em `docs/spec/`.
  Ideias e funcionalidades não têm direito autoral; a expressão do código tem.
- A spec descreve o que acontece, nunca como outro app implementa (sem nomes de funções, arquivos
  ou estruturas internas dele).

## Consequências
- Antes de implementar uma feature, a spec dela existe em `docs/spec/<feature>.md`.
- Bibliotecas de terceiros com licença compatível (MIT, BSD, Apache-2.0, zlib) podem ser usadas,
  com crédito no `NOTICE`.
- Não propor "acelerar portando o código de outro app": quebra a licença do projeto.

# 0003 — libghostty-vt como modelo do terminal

Data: 2026-10-19 · Status: aceita

## Contexto
Um terminal tem duas metades: o modelo (interpreta as sequências de escape e mantém a grade, o
scrollback, os modos e o Unicode) e a interface (desenha, cuida de fonte, cursor e seleção, e
transforma teclado em bytes). Recriar o modelo com a qualidade da libghostty seria o maior bloco
do projeto inteiro: parser VT, reflow, larguras Unicode, protocolos modernos, conformidade.

## Decisão
- O modelo do terminal é a libghostty-vt (do projeto Ghostty, licença MIT).
- Só a feature `terminal` do núcleo fala com ela. O resto do núcleo e o app conversam com a porta
  de entrada dessa feature, nunca com a libghostty diretamente.
- A interface do terminal é nossa: render em Metal, seleção, colagem, arrastar arquivos, atalhos.

## Consequências
- Trocar o modelo no futuro (por um próprio) afeta só a feature `terminal` do núcleo.
- A libghostty entra no `NOTICE` quando for incluída no repositório ou no app.
- Colagem e clipboard são responsabilidade nossa: a libghostty só informa o estado dos modos (por
  exemplo, bracketed paste).
- Não propor reescrever o parser VT sem antes medir um problema concreto da libghostty.

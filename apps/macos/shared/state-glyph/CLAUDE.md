# state-glyph (compartilhado do app)

## O que eu quero
- O sinal único de estado do app, igual em toda parte (`../../../../docs/adr/0035-work-frame.md`;
  components.stateGlyph de `../../../../docs/design/work-frame/tokens.json`): trabalhando (anel azul
  aberto em cima, girando), precisa de você (âmbar com halo), pronto (verde), falhou (vermelho),
  parado (contorno cinza) e em revisão (roxo). Cor no app quer dizer estado.

## O que eu não quero
- Uma tela desenhando o próprio sinal de estado, com outras cores ou outra forma.
- O anel girando fora de vista (fora da janela, escondido, janela coberta) ou com "Reduzir
  movimento": nada fora de vista custa (plano 17).
- Cor ou medida digitada: tudo de `DesignTokens` (o arquivo está em
  `../../../../tools/check_design_literals.py`).

## Como eu quero
- `StateGlyph.swift`: `GlyphState` (os seis estados) e `StateGlyphLook` (a cor, a espessura do anel
  por tamanho, o halo, o caminho do anel aberto em cima e `draw`, um quadro parado para quem desenha à
  mão, como a barra de abas, e para os snapshots).
- `StateGlyphView.swift`: o sinal como view, em camadas; o anel gira no servidor de desenho, sem
  redesenhar a janela, só enquanto pode ser visto. Tamanhos de desenho 7, 9, 10 e 14; a view guarda
  em volta o espaço do halo.
- Exceção à regra de `../CLAUDE.md` (só o que 2+ features já usam), decidida no plano 25: a aba usa
  já, e a árvore, o sino, o ⌘J, o quadro e a corrida usam nos planos 26 a 30.

## Como validar
- `make macos-test` passa: os seis estados com a cor do token, a espessura por tamanho, o halo, o
  anel que não gira fora de uma janela; com CADEX_SNAPSHOT_DIR, o teste salva state-glyphs.png (os
  seis nos quatro tamanhos) para pôr ao lado do mockup Anatomy.

# agent-band (compartilhado do app)

## O que eu quero
- A faixa que diz que um agente está agindo, com o mesmo visual nos dois lugares que a usam: a aba
  do preview que o agente dirige (`../../features/preview/CLAUDE.md`) e outros apps do Mac
  (`../../features/computer-use/CLAUDE.md`).

## O que eu não quero
- Uma faixa diferente por feature, nem texto com fundo pintado num campo de texto (ficava torto: o
  dono, 2026-11-15).

## Como eu quero
- `AgentBand.swift`: AgentBandView, uma pílula com o material HUD do sistema (escuro e translúcido),
  sombra leve, um ponto na cor de destaque que pulsa enquanto ela está à vista, o texto centrado numa
  linha e, no fim, uma tecla desenhada (`.key("esc")`, a faixa não pega clique) ou um botão em
  cápsula (`.button("Stop", ação)`, que vale no primeiro clique mesmo com outro app na frente).
  `inWindow` escolhe o desfoque dentro da janela (preview) ou atrás dela (painel no topo da tela).

## Como validar
- `make macos-test` passa; no app, a faixa do preview com o agente na aba e a do computer use agindo.

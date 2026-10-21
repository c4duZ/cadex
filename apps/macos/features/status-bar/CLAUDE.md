# status-bar (app macOS)

## O que eu quero
- Diretório atual navegável e ambiente.

## O que eu não quero
- Informação que muda a cada tecla causando redesenho da janela.

## Como eu quero
- `Breadcrumb.swift`: os pedaços do caminho ("Home › … › cadex") e as subpastas de um nível, puros
  e testados. `StatusBarView.swift`: a barra; cada pedaço abre um menu de subpastas (o do app, `apps/macos/shared/menus`, para cima) e a escolhida
  vai para quem montou a barra (onNavigate), que leva o terminal com foco até ela.
- A barra só se refaz quando a pasta muda, não a cada saída do terminal.
- Spec em `../../../../docs/spec/status-bar.md`. Status: trilha, menu e ambiente prontos.
- Fontes e medidas principais da interface vêm de UILooks (`../../shared/looks/CLAUDE.md`): zoom, densidade e fonte da interface, lidos ao montar a tela.

## Como validar
- `make macos-test` passa.

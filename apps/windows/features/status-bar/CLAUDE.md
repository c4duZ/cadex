# status-bar (app Windows)

## O que eu quero
- A barra de status do Mac: a trilha da pasta do terminal com foco ("Home › … › cadex"), o menu
  de subpastas de cada pedaço que leva o terminal até lá, e o ambiente à direita (Local ou a distro WSL).

## O que eu não quero
- `cd` mandado com um programa rodando: o menu fica apagado.

## Como eu quero
- Porta de entrada: `status_bar.zig` (StatusBar.draw devolve a pasta escolhida; quem monta manda o
  `cd`). `breadcrumb.zig`: os pedaços (Home, a unidade C: ou o compartilhamento \\servidor\pasta),
  puros e testados.
- Spec: `../../../../docs/spec/status-bar.md`.

## Como validar
- `make windows-app` compila os testes; a trilha conferida na VM.

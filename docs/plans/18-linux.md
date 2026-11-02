# 18 — Linux: núcleo, app GTK4 e release

Data: 2026-11-01 · Status: proposta

## O que eu quero
- O Cadex nativo no Linux sobre o mesmo núcleo, só Wayland, sem Electron/Tauri.
- Núcleo primeiro: `cd core && zig build test` verde no Linux antes de qualquer janela.
- `apps/linux/` em GTK4, uma feature por pasta, com os mesmos ids de comando do Mac e do
  Windows (`docs/adr/0005-every-action-is-a-command.md`).
- Instalação em um passo (AppImage ou .deb/.rpm) e o mesmo settings.json das outras
  plataformas.
- Uma feature por PR, com `CLAUDE.md` e testes, como no port do Windows.

## O que eu não quero
- X11, XWayland ou teste em X11.
- Começar a interface antes do núcleo passar no Linux.
- WebView para a interface; WebKitGTK só no preview (como o WebView2 no Windows).
- Poppler no binário (GPL-2.0): PDF por pdf.js.
- Dependência nova sem ADR e sem linha no `NOTICE`.
- Prometer paridade sem testar IME em Wayland.
- Refatorar o app Windows para "compartilhar" a casca: o custo é maior que duplicar.

## Como eu quero
Fases, uma por PR; o índice de PRs e os critérios de cada uma ficam na issue do repositório.

| # | fase | entrega | critério |
|---|---|---|---|
| 0 | docs | ADR 0021, este plano, manifestos | `make manifests` verde; dono aprova |
| 1 | núcleo | build, fs, pty, inotify, shell, CI | `zig build test` verde em Ubuntu 24.04 e Fedora 44 |
| 2 | janela e terminal | app GTK4, GL + Pango, teclado/IME/clipboard | `vim`/`htop`, IME no Mango |
| 3 | casca | abas, divisões, paleta, temas, configurações, atalhos, barra, spaces | paridade de comandos |
| 4 | documentos | explorer, busca, editor, Markdown, git, histórico | abrir/editar/buscar/commitar |
| 5 | previews e integrações | WebKitGTK, GStreamer, power, SSH, agents, updates, SNI, picker | preview, mídia, inibição, agentes |
| 6 | release | AppImage, .deb/.rpm, install.sh, CI, README | instalação limpa em um comando |

- `apps/linux/` segue `apps/windows/`: um build próprio que traduz `core/include/cadex.h` e
  liga a libcadex.a; pastas de feature com o mesmo nome do núcleo; shared/ só com o que
  2+ features usam.
- O build do app descobre as bibliotecas do sistema por `pkg-config`: GTK4 (>= 4.14),
  WebKitGTK 6.0 (>= 2.44), GStreamer, GdkPixbuf, HarfBuzz, FreeType e fontconfig.
- `make linux-core`, `make linux-app`, `make linux-run` e `make linux-package`.
- CI em `ubuntu:24.04` e `fedora:44`; smoke headless com Sway e `grim`.
- A bandeja usa StatusNotifierItem; no Mango ela não aparece. O README diz isso.
- O `NOTICE` ganha cada biblioteca na tarefa que a adiciona, não antes.

## Como validar
- `cd core && zig build test` nas duas imagens.
- `make check` continua verde no macOS.
- App no Fedora 44 + Mango: `vim`, `htop`, IME (Fcitx5/IBus), clipboard de imagem,
  notificações, `systemd-inhibit --list`, SSH, agents, element picker e self-update.
- `python3 tools/check_command_parity.py` passa com o terceiro app.
- Tamanho e memória medidos no README; release marcada **preview**.

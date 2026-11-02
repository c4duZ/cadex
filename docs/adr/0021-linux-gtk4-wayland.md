# 0021 — App Linux: GTK4, Wayland e renderização própria do terminal

Data: 2026-11-01 · Status: proposta · Revê `docs/adr/0001-macos-first-native-app.md` para o Linux

## Contexto
O macOS chegou à v2.2.1 e o Windows está em prévia, ambos sobre o núcleo em Zig com API C
(`docs/adr/0002-zig-core-with-c-api.md`). O ADR 0001 deixou Linux fora do escopo "por
enquanto". O dono pediu o port com todas as features, e a máquina de teste é Fedora 44 com
Mango 0.18.4 (Wayland).

O núcleo já é quase todo portátil. Faltam cinco costuras: o build (alvo padrão macOS e
`xcrun`), o sistema de arquivos (`renamex_np`, `copyfile`, `fstatat`/`fstat`,
`dirent.namlen`), o PTY (`proc_pidinfo`, `TIOCSWINSZ`, `forkpty`), a observação de arquivos
(FSEvents) e o shell padrão (`/bin/zsh`). O resto (processos, workspace, busca, editor,
Markdown, git) é POSIX.

## Decisão
- `apps/linux/` é um app novo em **Zig**, como o do Windows, sobre o mesmo núcleo e a mesma
  API C. Nada de importar arquivo de `core/`; nada de refatorar o app Windows.
- A interface é **GTK4** com os headers do sistema por `translate-c`, o mesmo método do
  mingw no Windows. `pkg-config` descobre GTK4 (>= 4.14), WebKitGTK 6.0 (>= 2.44),
  GStreamer, GdkPixbuf, HarfBuzz, FreeType e fontconfig.
- **Só Wayland.** Sem `WAYLAND_DISPLAY`, o app sai com uma mensagem clara. X11 e XWayland
  não são suportados nem testados.
- O terminal desenha em **GtkGLArea**: o núcleo entrega a grade pronta
  (`cadex_terminal_frame`), o app compõe fundos, seleção, cursor e glifos, e rasteriza os
  runs com **Pango** num atlas de texturas. Emoji colorido usa uma página RGBA do atlas.
- O editor é um **GtkTextView**: somente leitura para código, com os destaques e as dobras
  do tree-sitter do núcleo; editável para Markdown. Sem GtkSourceView.
- Preview web em **WebKitGTK 6.0**, o mesmo papel do WebView2 no Windows
  (`docs/adr/0014-webview2-on-windows.md`). Mídia em **GStreamer** por
  `GtkMediaFile`/`GtkVideo`; imagens em GdkPixbuf; PDF por **pdf.js** dentro do preview.
  **Poppler não entra** (GPL-2.0).
- Energia, notificações e bandeja por **GDBus**: `org.freedesktop.login1.Manager.Inhibit`,
  `org.freedesktop.Notifications` e `org.kde.StatusNotifierItem` + DBusMenu. Sem
  libappindicator.
- Pacotes: **AppImage + .deb + .rpm** com GTK/WebKit/GStreamer do sistema. x86_64 no v1.
  O AppImage se atualiza pelo `latest.json` assinado; .deb/.rpm só avisam.
- Atalhos com **Ctrl+Shift**, como no Windows, para o mesmo `settings.json` servir nas
  três plataformas. `Ctrl+letra` continua indo ao shell.
- A versão é a mesma do Mac/Windows, marcada **preview** no README.

## Por que não as outras
- **Wayland/X11 crus + widgets próprios:** repete o maior custo do port do Windows (a
  camada de widgets) e ainda exige IME (text-input-v3), clipboard, arrastar-e-soltar e
  acessibilidade. Meses a mais sem ganho para quem usa.
- **Qt:** C++ com moc, interop ruim com Zig e um segundo toolchain.
- **Electron/Tauri:** proibidos pelo ADR 0001; o app deixaria de ser leve.
- **GTK3:** legado; o WebKitGTK 6.0 é GTK4.
- **Flatpak primeiro:** o sandbox atrapalha PTY, pastas do workspace e SSH; fica para
  depois do v1.
- **Poppler:** GPL-2.0; o pdf.js é Apache-2.0 e roda no preview que já existe.
- **SNI no Mango:** o Mango não tem host de StatusNotifierItem; a bandeja aparece no
  GNOME (com extensão) e no KDE, e fica invisível no Mango. É uma diferença documentada,
  não um bug.

## Consequências
- Dependência de runtime (GTK4, WebKitGTK, GStreamer) e ~30–40 MB de RSS; o AppImage não
  carrega o WebKit. É o preço de não reescrever uma camada de widgets.
- O renderer GL + Pango é o maior risco técnico. A fase 2 começa com um spike de um painel;
  se não atingir o orçamento de peso, o fallback é Cairo/Pango por célula e fica registrado
  aqui.
- O `make check` do Mac continua sendo a validação do Mac; o Linux tem CI próprio em
  Ubuntu 24.04 e Fedora 44.
- Cada feature tem pasta própria com `CLAUDE.md` e testes, como nas outras plataformas.
- O app Linux não compartilha módulos de interface com o Windows; compartilha o núcleo, o
  catálogo de temas, a fonte Phosphor e os ícones de arquivo. Duplicar a casca é mais
  barato do que abstrair duas APIs gráficas diferentes.

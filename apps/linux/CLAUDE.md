# apps/linux — app Linux

## O que eu quero
- Um app Linux nativo sobre o mesmo núcleo, só Wayland, com todas as features do Mac.
- O port segue o plano 18 (`../../docs/plans/18-linux.md`) e o ADR 0021
  (`../../docs/adr/0021-linux-gtk4-wayland.md`).

## O que eu não quero
- X11, XWayland ou teste em X11.
- WebView para a interface (a exceção é a feature preview, que é uma página web).
- Lógica de negócio no app: ela mora no núcleo e chega pela API C
  (`../../core/include/cadex.h`), mesmo o app sendo Zig. Nada de importar arquivo de
  `../../core/`.
- Refatorar o app Windows para compartilhar a casca: a duplicação é mais barata que
  abstrair duas APIs gráficas.

## Como eu quero
- Zig com GTK4, Wayland e os headers do sistema por translate-c. O build do app descobre
  GTK4, WebKitGTK, GStreamer, GdkPixbuf, HarfBuzz, FreeType e fontconfig por pkg-config.
- Uma pasta por feature, com os mesmos nomes do núcleo e do Mac/Windows; shared/ só com o
  que 2+ features usam. A árvore é criada na fase 2 do plano 18.
- O terminal desenha em GtkGLArea com um atlas de glifos do Pango; o editor é um
  GtkTextView com os destaques do núcleo; o preview é WebKitGTK; a mídia é GStreamer.
- Energia, notificações e bandeja por GDBus (login1.Inhibit, org.freedesktop.Notifications
  e StatusNotifierItem).
- Sem WAYLAND_DISPLAY, o app sai com uma mensagem clara.
- O build tem de compilar no Ubuntu 24.04 (GTK 4.14) e no Fedora 44.

## Como validar
- CI em ubuntu:24.04 e fedora:44: testes do núcleo, build do app e smoke headless com
  Sway e grim.
- `python3 ../../tools/check_command_parity.py` com o terceiro app.
- No Fedora 44 + Mango: vim, htop, IME (Fcitx5/IBus), clipboard de imagem, notificações,
  systemd-inhibit --list, SSH, agents, element picker e self-update.

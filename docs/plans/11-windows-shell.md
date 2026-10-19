# Plano 11 — Abas, divisões, paleta, tema e configurações no Windows

Depende de: plano 10 · Features: tabs, command-palette, shortcuts, themes, settings, status-bar
(app Windows) · Decisões: `docs/adr/0005-every-action-is-a-command.md`,
`docs/adr/0008-phosphor-icons.md`, `docs/adr/0012-windows-zig-win32-d3d11.md` · Specs a mudar:
shortcuts (mapa do Windows), settings (onde fica o arquivo).

## O que eu quero
- O mesmo app do Mac em volta do terminal: abas, divisões, paleta (com seções, prefixos e o menu do
  "+"), temas (os 46, Caffeine padrão, imagem de fundo), janela de configurações e status bar.
- Os mesmos ids de comando do Mac. Um teste confere que todo comando do Mac existe no Windows, ou
  está marcado como só de uma plataforma.
- Um lugar só para o que os dois apps leem: catálogo de temas, fonte Phosphor, ícones Material,
  padrões de configuração e de atalhos. Hoje estão dentro de `apps/macos/`.
- settings.json no %APPDATA%\Cadex, mesmo formato do Mac: o arquivo do dono serve nas duas máquinas.

## O que eu não quero
- Cópia do catálogo de temas ou dos ícones dentro de apps/windows.
- Controle do Win32 com a cara do Windows 95 (ListView, Edit padrão) no meio da interface do Cadex.
- Ação que só existe num botão ou menu (ADR 0005).

## Como eu quero
**Fases:**
- **A. Recursos comuns.** Mover o catálogo (`apps/macos/features/themes/Resources/catalog.json`), a
  fonte e os ícones (`apps/macos/shared/icons/Resources/`) para uma pasta de recursos na raiz, lida
  pelos dois apps. O Mac continua passando no `make check`.
- **B. Camada de interface.** apps/windows/shared/ui: Direct2D e DirectWrite, layout simples,
  rolagem, foco, hover, campo de texto (com IME e seleção), lista virtual, menu de contexto próprio,
  ícones Phosphor por fonte privada do DirectWrite. Base para todos os planos seguintes.
- **C. Comandos, paleta e atalhos.** Registro de comandos, paleta, mapa de atalhos. Decidir com o
  dono a tecla do ⌘ no Windows (Ctrl+Shift, como o Windows Terminal, ou Alt) e registrar na spec de
  shortcuts antes do código.
- **D. Abas e divisões.** Barra de abas na barra de título, árvore de painéis, divisor arrastável,
  foco, escurecer sem foco, mesmos comandos do Mac.
- **E. Tema, configurações e status bar.** Temas do catálogo comum, janela de configurações com as
  mesmas páginas, status bar com o ambiente (Local ou a distro WSL).

## Como validar
- `make check` passa no Mac; testes do app Windows passam na VM.
- Teste de paridade de comandos passa. O settings.json do Mac abre no Windows sem perder nada.
- Na VM: abrir, dividir, fechar, trocar tema, mudar atalho, tudo pela paleta também.
- Status na tabela de `docs/plans/README.md`.

# Plano 15 — Mais temas e mais personalização visual

Depende de: plano 14 (idiomas) concluído · Features: themes, settings, terminal, tabs, spaces,
command-palette · Decisões: `docs/adr/0008-phosphor-icons.md`, `docs/adr/0005-every-action-is-a-command.md`,
`docs/adr/0015-english-default-two-languages.md`.

## O que eu quero
- Muito mais temas, e bons: as paletas oficiais dos temas populares, com todas as variantes, e um
  catálogo grande vindo do tinted-theming (base16/base24, MIT). Pedido do dono em 2026-10-20, a
  partir da pesquisa com terminais (Ghostty, WezTerm, Kitty, iTerm2, Warp, Windows Terminal) e
  apps de workspace (VS Code, Zed, Warp, Wave, Arc, Raycast).
- Os temas que vieram do tweakcn com cores de terminal de verdade: hoje todos usam a mesma paleta
  ANSI de base e ficam iguais dentro do terminal.
- Personalizar o visual com poucos controles que mudam muito: um tema para o claro e outro para o
  escuro, a cor de destaque, contraste mínimo e um modo de alto contraste, o escurecimento dos
  painéis sem foco, a fonte do terminal (altura de linha, espaçamento, ligaduras), zoom e
  densidade da interface com a fonte dela, e cores por space e por aba.
- Tudo nos dois apps, Mac e Windows; cada opção também um comando no ⌘K (ADR 0005), cada texto em
  par inglês/português (ADR 0015), cada escolha numa chave do settings.json.

## O que eu não quero
- Por enquanto (o dono, 2026-10-20): rastro animado do cursor, posição/encaixe/tinta da imagem de
  fundo, variações do ícone do app, ligar e desligar itens da barra de status.
- Centenas de chaves de cor como o VS Code (cerca de 600): os temas viram um quebra-cabeça e
  quebram quando a interface muda. Poucos valores com sentido; o resto é derivado.
- Tema sem licença clara, Monokai Pro (produto pago), o repositório kitty-themes (GPL) e logos ou
  marcas: só as paletas abertas, com o nome do tema.
- Efeito que ignore "Reduzir transparência" e "Reduzir movimento" do sistema.
- Cor escolhida pelo usuário deixando texto ilegível: contraste sempre conferido.

## Como eu quero
**Fases:**
- **A. Temas.** O gerador `tools/themes/build_catalog.py` passa a ler três fontes: as paletas
  oficiais com variantes (Catppuccin Latte/Frappé/Macchiato/Mocha; Rosé Pine Main/Moon/Dawn; Tokyo
  Night Night/Storm/Moon/Day; Kanagawa Wave/Dragon/Lotus; Gruvbox e Everforest, claro e escuro em
  três contrastes; GitHub, incluindo alto contraste e para daltônicos; Ayu Dark/Mirage/Light; One
  Dark/Light; Nightfox; Night Owl; Solarized), o tinted-theming base16/base24 em quantidade, e os
  presets do tweakcn com ANSI próprio derivado das cores deles. As cores de interface (chrome,
  panel, panelBorder, tabActive, field, text, secondaryText, accent) saem dos papéis do base16 (e
  dos guias de estilo de cada tema oficial), ajustadas em OKLCH; o build recusa tema que não passe
  na checagem de contraste. Cada tema leva autor e fonte; as fontes entram no `NOTICE`. A página
  de temas (`apps/macos/features/settings/ThemesPage.swift` e a do Windows) ganha busca e filtro
  claro/escuro. Importar tema (.itermcolors, Ghostty, base16) e uma pasta de temas do usuário em
  Application Support/Cadex/themes (themes no Mac e no Windows). O mapeamento base16 → Cadex e a
  escolha das fontes em quantidade viram ADR ao começar a fase.
- **B. Claro, escuro e destaque.** Com o modo "seguir o sistema", um tema para o claro e outro
  para o escuro (appearance.lightTheme, appearance.darkTheme), como Ghostty, Zed e Windows
  Terminal. A cor de destaque escolhível: a do tema ou uma própria (appearance.accent), pintando
  aba ativa, seleção, foco e ícones ligados; o texto por cima vira preto ou branco pelo contraste.
  Features: themes, settings.
- **C. Contraste e leitura.** Contraste mínimo do texto do terminal (terminal.minimumContrast,
  razão WCAG), no shader do Mac e no do Windows. Modo de alto contraste (appearance.highContrast):
  texto da interface e do terminal a 7:1 (WCAG AAA), bordas e divisórias mais fortes, sem
  transparências, aba e painel com foco reforçados; liga sozinho com "Aumentar contraste" do
  macOS e com o modo de contraste do Windows. Escurecimento dos painéis sem foco ajustável
  (tabs.unfocusedDim), hoje fixo. Fonte do terminal: altura de linha (terminal.lineHeight),
  espaçamento entre letras (terminal.letterSpacing) e ligaduras e variações tipográficas
  (terminal.fontFeatures). Features: terminal, tabs, themes, settings.
- **D. Interface e cores de trabalho.** Zoom e densidade da interface (appearance.uiZoom,
  appearance.density: compacta ou normal) e uma fonte da interface separada da do terminal
  (appearance.uiFont, appearance.uiFontSize), como o Zed. Cor por space e por aba, pelo clique
  direito e pelo ⌘K, salva no spaces.json, pintando a barra de abas e o painel lateral. Ordem das
  camadas, de baixo para cima: tema, destaque, cor do space, cor da aba. Features: spaces, tabs,
  settings, themes.

## Como validar
- `make check` passa a cada fase; o build do catálogo recusa tema abaixo do contraste mínimo.
- Fase A: a página de temas acha um tema pela busca e filtra claro/escuro; os temas do tweakcn
  mostram cores diferentes no `ls --color`; um .itermcolors importado aparece e funciona.
- Fase B: trocar o modo do macOS troca entre os dois temas escolhidos; com um destaque claro, o
  texto da aba ativa fica escuro, e o contrário.
- Fase C: com alto contraste ligado, todo texto passa 7:1; "Aumentar contraste" do macOS liga o
  modo sozinho; a altura de linha e as ligaduras mudam o terminal na hora.
- Fase D: o zoom muda a interface inteira e não o terminal; a cor de um space volta ao reabrir.
- Cada opção nova existe no ⌘K e no settings.json, nos dois idiomas e nos dois apps.

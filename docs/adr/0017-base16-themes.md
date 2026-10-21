# 0017 — Temas em quantidade do base16/base24, com contraste conferido

Data: 2026-10-20. Status: aceita.

## Contexto
O plano 15 pede muito mais temas. Até aqui eram 46: as paletas oficiais de 10 temas abertos e os
presets do tweakcn. Os terminais que o dono comparou trazem centenas (Ghostty e WezTerm vêm com
o catálogo do iTerm2-Color-Schemes; o Zed e o Warp, com o base16). Para ter quantidade é preciso
uma fonte grande, de licença clara, num formato que diga o papel de cada cor, e não só a cor.

## Decisão
- Fonte em quantidade: os esquemas base16 e base24 do tinted-theming/schemes (MIT), num commit
  fixado em `tools/themes/build_catalog.py`. O iTerm2-Color-Schemes ficou de fora porque traz só
  as cores do terminal, sem os papéis da interface, e mistura licenças. O kitty-themes ficou de
  fora por ser GPL.
- Quando o mesmo esquema existe em base16 e base24, vale o base24, que traz as cores brilhantes
  próprias. Ficam de fora:
  - os portes dos temas que já vêm das paletas oficiais (Catppuccin, Gruvbox, GitHub…), porque o
    original é mais fiel;
  - o Monokai Pro, que é produto pago.

  Esquemas com nomes "-dark"/"-light" do mesmo tema viram uma família com as duas versões.
- Mapeamento para o Cadex:
  - **Terminal:** segue o do próprio tinted-theming. ANSI 0–7 = base00, 08, 0B, 0A, 0D, 0E, 0C
    e 05; 8 = base03; 9–14 = base12, 14, 13, 16, 17 e 15 (no base16, 08, 0B, 0A, 0D, 0E e 0C);
    15 = base07. Fundo base00, texto e cursor base05, seleção base02.
  - **Interface:** painéis base00, moldura base01, borda base02, texto base05, texto secundário
    base04, destaque base0D (o azul, que o base16 dá a títulos e funções). A aba ativa é a moldura
    com 22% do destaque, como nos outros temas.
- Contraste conferido no build, igual para as três fontes:
  - Texto do terminal abaixo de 4,0:1 (WCAG) recusa o tema, porque mexer nele mudaria a cara do
    tema. O limite é 4,0 e não o 4,5 do AA porque o Solarized Light oficial tem 4,1.
  - O texto da interface (4,5:1) e o secundário (3:1), sobre os painéis e sobre a moldura, andam
    na luminosidade OKLCH, com o mesmo tom e saturação, até passar. Se não passam, o tema é
    recusado.
  - O destaque precisa de 2:1 sobre a moldura.
- Temas quase iguais (distância média OKLab abaixo de 0,025 nas cores que fazem a cara do tema)
  entram uma vez só. Ganha o primeiro na ordem oficial, tweakcn, base24, base16.
- Os presets do tweakcn ganham ANSI próprio. Cada cor ANSI é a cor do preset mais próxima no tom
  (primary, chart, destructive…). Se nenhuma está perto, a cor é feita no tom ANSI com a
  luminosidade e a saturação do preset.
- O catálogo é um arquivo só (`catalog.json`, ~280 KB), lido quando preciso e não guardado: o app
  mantém só o tema em uso. A lista inteira é lida quando a página de temas ou o ⌘K a mostram.

## Consequências
- São ~370 temas em vez de 46. A página de temas tem busca e filtro claro/escuro, e só os
  cartões que aparecem na tela existem.
- Um esquema base16 com papéis trocados (ex.: base01 colorido) é recusado pelo contraste em vez
  de entrar estranho.
- Atualizar os esquemas é trocar o commit no script e rodar de novo. Os recusados aparecem na
  saída do build.

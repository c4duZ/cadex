# Plano 3 — Janela com a cara do Terax, tema e configurações

Depende de: planos 1 e 2 · Features: themes, settings, status-bar (app); a casca da janela fica em
`apps/macos/app/` · Specs a escrever: themes, settings, status-bar.

## O que eu quero
- **Visual do Terax**, refeito: barra de título unificada com as abas dentro dela (botões de janela à
  esquerda, abas, botão "+" com menu Terminal/Editor/Preview/Git Graph, campo de busca e botão de
  configurações à direita); painel lateral recolhível à esquerda com um trilho de ícones (Explorer,
  Source Control) e área de conteúdo (vazia até os planos 4 e 6); barra de status embaixo com a
  pasta atual navegável e o ambiente; cantos arredondados e espaçamentos do Terax.
- **Tema:** um tema padrão escuro no estilo do Terax (fundo, texto, seleção, cursor, 16 cores ANSI,
  cores da interface) e um claro; seguir o modo do sistema por padrão; o terminal usa a paleta do
  tema (o núcleo recebe as cores); imagem de fundo com opacidade e desfoque (desligada por padrão).
- **Importar os temas do Terax:** o usuário escolhe arquivos de tema exportados pelo Terax e eles
  viram temas do Cadex com as mesmas cores.
- **Configurações:** janela (⌘,) com Geral (shell, confirmação ao fechar, abrir na pasta), Terminal
  (fonte, tamanho, espaçamento, cursor, piscar, histórico, Option como Meta), Aparência (tema,
  modo, imagem de fundo), Atalhos (do plano 2, editáveis). Mudanças valem na hora em todas as janelas.

## O que eu não quero
- Copiar CSS, ícones ou arquivos do Terax: o visual é refeito a partir de prints do app e do que o
  dono descrever. Ícones são Phosphor (`docs/adr/0008-phosphor-icons.md`), registrados no `NOTICE`.
- Transparência ou desfoque ligados por padrão (custam desempenho a cada quadro).
- Ler o formato de tema do Terax no código dele (ADR 0004): o formato é levantado a partir de
  arquivos exportados que o dono fornece (pedir um ou dois antes de começar a fase D).
- Preferência guardada em mais de um lugar.

## Como eu quero
**Onde estamos.** Janela padrão do macOS com abas e divisões simples (plano 2). O fundo do terminal
vem do quadro do núcleo (`core/features/terminal/render.zig`, cores padrão da libghostty). A paleta
da libghostty pode ser trocada (Terminal.colors / palette; procurar em
core/zig-pkg/ghostty-*/src/terminal/color.zig e Terminal.zig).

**Fases:**
- **A. Casca:** NSWindow com titlebarAppearsTransparent e fullSizeContentView; barra de abas
  desenhada pelo app dentro da área de título; NSSplitView para painel lateral + área de trabalho;
  barra de status. Comandos: alternar painel lateral, foco na busca.
- **B. Tema:** modelo de tema (tokens de interface + paleta do terminal) em arquivo JSON do Cadex;
  temas embutidos (escuro e claro); API C para o núcleo receber fundo, texto, cursor e as 16 cores
  (e responder corretamente às consultas de cor dos programas, OSC 10/11).
- **C. Configurações:** um arquivo de preferências único (o mesmo do plano 2) e uma janela nativa;
  observar mudanças e aplicar ao vivo (fonte refaz o GlyphAtlas, `apps/macos/features/terminal/GlyphAtlas.swift`).
- **D. Importar temas do Terax:** com os arquivos de exemplo do dono em
  `apps/macos/features/themes/` (pasta de testes), escrever o conversor e o teste de mesmas cores.
- **E. Imagem de fundo** com opacidade e desfoque, só quando ligada.

## Como validar
- `make check` passa ao fim de cada fase.
- Testes: tema JSON lido e validado (cor inválida recusada com mensagem); conversão de tema do Terax
  gera as mesmas cores dos exemplos; preferências salvas e relidas; mudança de fonte recalcula as
  métricas.
- Manual, com print da janela lado a lado com o Terax: barra de título com abas, painel lateral
  recolhendo e abrindo, barra de status com a pasta atual, tema claro/escuro seguindo o sistema,
  `ls --color` e `vim` com as cores do tema.
- Atualizar specs, `CLAUDE.md` das features e o status em `docs/plans/README.md`.

## Situação (2026-10-19)
Fases A, B, C e E feitas. A fase D (importar temas do Terax) saiu do plano com o dono: os temas do
Terax são os mesmos que o Cadex traz embutidos (46, do tweakcn e de paletas oficiais, gerados por
`tools/themes/build_catalog.py`) e ninguém usa tema próprio. Ícones Phosphor
(`docs/adr/0008-phosphor-icons.md`). A janela de configurações segue o tema. Falta conferir à mão:
tema claro/escuro seguindo o sistema e `ls --color` e `vim` com as cores do tema.


# Plano 5 — Visualizadores: código, Markdown, mídia e preview web

Depende de: plano 4 · Features: editor (núcleo e app), markdown (núcleo e app), media-preview,
preview (app) · Decisões: `docs/adr/0006-editor-reads-code-edits-markdown.md` · Specs a escrever:
editor, markdown, media-preview, preview.

## O que eu quero
- **Código** (ADR 0006): abrir qualquer arquivo de texto numa aba com números de linha, setinha de
  dobrar, destaque de sintaxe e linha atual destacada; edições pequenas com o que o NSTextView já dá
  (digitar, desfazer, ⌘F, ⌘S salva); arquivo grande abre sem travar (acima do limite, sem destaque);
  binário avisa em vez de mostrar lixo; arquivo alterado no disco recarrega se não houver edição.
  Linguagens do MVP: TypeScript/JavaScript, Python, Rust, Go, Swift, Zig, C/C++, Java, HTML, CSS,
  JSON, YAML, TOML, Shell, Markdown.
- **Markdown:** alternar entre texto e renderizado (GitHub Flavored: tabelas, listas de tarefa, blocos
  de código com destaque, imagens locais); ao editar, autocomplete de caminho ao digitar `](`, de título
  depois de `#`, de nota ao digitar `[[`; ⌘+clique num link abre o arquivo no título certo; link
  quebrado sublinhado; painel "quem aponta pra cá".
- **Mídia:** imagem (zoom, ajustar à janela), vídeo e áudio com controles do sistema, PDF com páginas
  e busca; outros formatos pelo Quick Look.
- **Preview web:** aba com página web, barra de endereço, voltar/avançar/recarregar; URLs locais
  (`http://localhost:porta`) que aparecem na saída do terminal viram uma oferta "abrir no preview".

## O que eu não quero
- Language server, autocomplete de código, vim ou formatar ao salvar (ADR 0006).
- Biblioteca de editor de terceiros; o editor é o NSTextView com TextKit 2.
- Recolorir o arquivo inteiro a cada tecla: o tree-sitter reanalisa só o trecho alterado.
- HTML do Markdown executando script, ou o preview web acessando arquivos e a API do app.
- Biblioteca para o que o sistema já faz em mídia.

## Como eu quero
**Onde estamos.** Abas e painel lateral existem (planos 2 e 3); o explorer e a busca abrem arquivos
(plano 4). Manifestos com o que cada feature quer: `core/features/editor/CLAUDE.md`,
`core/features/markdown/CLAUDE.md`, `apps/macos/features/editor/CLAUDE.md`,
`apps/macos/features/markdown/CLAUDE.md`, `apps/macos/features/media-preview/CLAUDE.md`,
`apps/macos/features/preview/CLAUDE.md`.

**Fases:**
- **A. tree-sitter no núcleo:** incluir o tree-sitter (C, MIT) e as gramáticas do MVP como
  dependências em `core/build.zig.zon`, compiladas pelo Zig; cada uma entra no `NOTICE` com a
  licença. API C: abrir documento (linguagem pelo nome do arquivo), editar (faixa trocada),
  faixas de destaque (início, fim, tipo) e regiões de dobra para um intervalo de linhas. Consultas
  de destaque (highlights.scm) de cada gramática com licença compatível.
- **B. Visualizador de código (app):** NSTextView com TextKit 2, régua de números de linha e
  setinhas de dobra, linha atual, cores do tema (plano 3) por tipo de trecho; abrir em aba; ⌘S salva
  pela API do explorer (respeitando o workspace); recarregar quando o disco muda.
- **C. Markdown:** decidir em ADR como renderizar (proposta: cmark-gfm, C, licença BSD, gerando HTML
  sanitizado, mostrado numa WKWebView sem JavaScript; a alternativa nativa com NSAttributedString
  perde tabelas e blocos de código). Índice de títulos, links e `[[nota]]` no núcleo, atualizado pela
  observação de arquivos; autocomplete, ⌘+clique, links quebrados e "quem aponta pra cá" no app,
  ligados ao editor pela porta de entrada dele. Âncoras no formato do GitHub.
- **D. Mídia:** NSImageView/ImageIO, AVPlayerView, PDFView, QLPreviewView, escolhidos pelo tipo do
  arquivo.
- **E. Preview web:** WKWebView com configuração isolada (sem ponte para o app); o núcleo do terminal
  avisa URLs locais vistas na saída (detecção no quadro ou na linha) e o app mostra a oferta.

## Como validar
- `make check` passa ao fim de cada fase.
- Testes do núcleo: destaque de um arquivo de exemplo por linguagem confere tipos esperados nas
  posições certas; edição incremental atualiza só o trecho; índice de Markdown com link para
  arquivo, para título, wiki, link quebrado e "quem aponta pra cá"; âncora "Decisão Final" vira
  `#decisão-final`.
- Testes do app: escolha do visualizador pelo tipo do arquivo; sanitização remove `<script>`.
- Manual, com print: abrir `core/features/terminal/render.zig` com destaque e dobra; abrir um
  arquivo de 100 MB sem travar; editar e salvar um Markdown com autocomplete de `](` e `[[`; abrir
  `docs/cadex-icon.png`, um PDF e um vídeo; `python3 -m http.server` oferece o preview.
- Atualizar specs, `CLAUDE.md` das features e o status em `docs/plans/README.md`.

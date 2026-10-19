# Plano 12 — Arquivos, visualizadores e git no Windows

Depende de: plano 11 · Features: explorer, search, editor, markdown, media-preview, preview,
source-control, git-history (app Windows) · Decisões: `docs/adr/0006-editor-reads-code-edits-markdown.md`,
`docs/adr/0011-material-file-icons.md`, `docs/adr/0012-windows-zig-win32-d3d11.md`.

## O que eu quero
- Tudo o que os planos 4, 5 e 6 entregaram no Mac, no Windows, com o mesmo comportamento das specs:
  explorer com árvore, ícones e observação do disco; busca por nome e por conteúdo; editor de código
  com tree-sitter; Markdown renderizado e editável; imagem, vídeo, áudio e PDF; preview web; source
  control e grafo do git.
- Mídia pelos componentes do Windows: WIC para imagem, Media Foundation (IMFMediaEngine) para vídeo
  e áudio, Windows.Data.Pdf para PDF. Preview web pelo WebView2, que já vem no Windows 11.

## O que eu não quero
- PDFium, FFmpeg ou um navegador dentro do app: o Windows 11 já tem tudo isso.
- O WebView2Loader.dll solto ao lado do exe se for possível achar o runtime direto; se não for,
  registrar o motivo em ADR e no NOTICE.
- Lógica de árvore, busca, diff ou grafo reescrita no app: ela já está no núcleo.

## Como eu quero
**Fases** (uma ou mais sessões cada, nessa ordem):
- **A. Explorer e workspace.** Árvore virtual na camada de interface, ícones Material do recurso
  comum, renomear no lugar, menu de contexto, arrastar para o terminal, observação do disco.
- **B. Busca.** Ctrl+P por nome e busca de conteúdo, mesmos resultados do núcleo.
- **C. Editor e Markdown.** Texto do editor pelo DirectWrite com os realces do tree-sitter do núcleo,
  números de linha, dobra, linha atual; Markdown renderizado (md4c no núcleo) e edição com o
  autocomplete de links e links quebrados.
- **D. Mídia.** WIC, IMFMediaEngine e Windows.Data.Pdf, chamados pelo ABI de COM/WinRT declarado à
  mão. É o maior risco técnico do plano: começar por um teste mínimo de cada um na VM.
- **E. Preview web.** WebView2 só na feature preview; https por padrão, como no Mac.
- **F. Git.** Source control (status, diff, stage, commit, push, pull) e grafo do histórico, com o
  git.exe do Git for Windows e o aviso quando ele não estiver instalado.

## Como validar
- `make check` passa no Mac; testes do app Windows passam na VM.
- Critérios de aceite das specs dessas features conferidos na VM, marcados com "(Windows)".
- Status na tabela de `docs/plans/README.md`.

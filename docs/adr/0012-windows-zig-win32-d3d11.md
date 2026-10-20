# 0012 — App Windows: Zig com Win32 e Direct3D 11

Data: 2026-10-19 · Status: aceita (revista em 2026-10-20: as declarações do app vêm dos headers)

## Contexto
O macOS chegou à v1.0.0 (planos 1 a 8). O dono pediu para começar o Windows mantendo todas as
features. O ADR 0001 deixou a stack em aberto entre C++ com Win32/Direct3D e C# com WinUI. O núcleo
(ADR 0002) já é Zig com API C, e a interface macOS tem cerca de 18 mil linhas de Swift que vão ser
reescritas para o Windows.

## Decisão
- O app Windows fica em `apps/windows/`, escrito em **Zig**, sobre **Win32** puro: janela, mensagens,
  DPI por monitor, área de transferência e IME pelas APIs do sistema.
- Desenho: um device **Direct3D 11** por processo, uma swap chain por janela composta pelo
  DirectComposition (permite o Mica atrás), e **Direct2D com DirectWrite** desenhando tudo nela,
  inclusive o terminal: glifos posicionados na grade com DrawGlyphRun, e layouts em cache para
  emoji e grafemas compostos. (Revisto em 2026-10-20: o atlas de glifos em shaders próprios, como o
  Metal no Mac, fica para quando a medição pedir; escrever shaders sem poder rodar era risco demais.)
- Mídia e web pelos componentes do sistema: WIC (imagem) e WebView2 nas páginas web (preview,
  Markdown renderizado) e no que ele toca (GIF, SVG, vídeo, áudio e PDF). (Revisto em 2026-10-20 pelo
  `0014-webview2-on-windows.md`: Media Foundation e Windows.Data.Pdf pediam ABI WinRT e controles à
  mão, sem como testar.)
- **Só Windows 11** (x64 e arm64): permite Mica, cantos arredondados e APIs novas sem caminho
  alternativo para o Windows 10.
- O app fala com o núcleo **só pela API C** (`core/include/cadex.h`), mesmo sendo Zig dos dois lados:
  importa o header, liga a `libcadex.a`. Nada de `@import` de arquivo de `core/`.
- As declarações de Win32, Direct3D, DirectWrite e COM do app saem dos headers do Windows que o
  Zig já traz (mingw-w64), pelo `translate-c`, a partir de um header que lista só o que o app
  inclui (`apps/windows/shared/win32/`). Sem pacote de bindings de terceiros. O núcleo, que usa
  poucas funções, segue com as dele escritas à mão (`core/shared/win32.zig`).
- Testes de verdade numa VM com Windows 11 ARM neste Mac; o build sai daqui por cross-compile.

## Por que não as outras
- C++ com Win32: mesmo peso, mas um segundo compilador (MSVC), que só roda no Windows. Com Zig, o
  `.exe` sai do Mac, do mesmo jeito que o núcleo.
- C# com WinUI 3: interface mais rápida de escrever, mas traz .NET e o Windows App SDK: binário
  muito maior, abertura mais lenta e instalação com dependência (contra o ADR 0007).
- Pacote de bindings gerados (zigwin32): dezenas de MB de código gerado para usar uma fração; vira
  dependência a acompanhar a cada versão do Zig.
- Tabelas COM escritas à mão (a decisão de 2026-10-19): o app é escrito sem poder rodar no Windows
  até a VM existir, e um método fora de ordem numa tabela só aparece como crash. Os headers do
  mingw que vêm com o Zig dão a ordem exata, sem dependência nova.

## Consequências
- Não há controles prontos com a cara do Cadex: lista, árvore, campo de texto, rolagem e menus são
  desenhados pelo app, numa camada de interface em `apps/windows/shared/ui/`. É o maior custo do port.
- O que as duas plataformas precisam e não é desenho (catálogo de temas, ícones, padrões de
  configuração e de atalhos) fica num lugar só, lido pelos dois apps, em vez de copiado.
- Cada comando do Mac existe no Windows com o mesmo id (ADR 0005); o que for só de uma plataforma
  é marcado como tal.
- Atalhos: ⌘ vira Ctrl; no terminal, os que colidem com o shell usam Ctrl+Shift (como o Windows
  Terminal). A spec de shortcuts registra o mapa.
- Não propor trocar para WinUI, Electron ou C# "para andar mais rápido": foi considerado aqui.

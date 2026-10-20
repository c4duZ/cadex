# 0014 — WebView2 no Windows: declarações do SDK, loader ao lado do exe, mídia na página

Data: 2026-10-20 · Status: aceita (revê a linha de mídia do ADR 0012)

## Contexto
O preview web, o Markdown renderizado e parte da mídia precisam de uma página web no app Windows
(no Mac, WKWebView). O ADR 0012 escolheu WebView2 só para o preview e Media Foundation e
Windows.Data.Pdf para vídeo, áudio e PDF. O app é Zig compilado no Mac, sem MSVC e sem uma máquina
Windows para testar até a VM existir; o plano 12 pediu achar o runtime sem o WebView2Loader.dll
solto, ou registrar o motivo.

Três peças: as interfaces COM do WebView2 (ICoreWebView2Environment, Controller, handlers), o jeito
de criar o ambiente, e onde mora a página.

## Decisão
- **Interfaces:** do `WebView2.h` do pacote NuGet Microsoft.Web.WebView2 (licença BSD de 3 cláusulas
  da Microsoft, no `NOTICE`), versão fixada com sha256 em `tools/webview2_sdk.py`. O script tira só
  as tabelas em C (CINTERFACE, na ordem do MIDL) das interfaces que o app usa, os enums e structs
  delas e os ids, para `apps/windows/shared/webview/sdk/` (`webview2.h`, `iids.zig`); o `sdk.h` do
  app inclui esse header, e o translate-c dá as tabelas como as dos headers do mingw. O header
  inteiro tem 2,9 MB e pede o `EventToken.h`, que o mingw não tem; o `zig fetch` não aceita `.nupkg`.
- **Loader:** o `WebView2Loader.dll` da Microsoft (do mesmo pacote, redistribuível pela mesma
  licença), instalado ao lado do `Cadex.exe` pelo `build.zig` e carregado com `LoadLibraryExW` só da
  pasta do exe no primeiro painel web. Sem ele o app abre igual e o painel diz o que falta.
- **Handlers:** structs Zig com a tabela traduzida (`shared/webview/com.zig`), contando as
  referências do dono: um retorno do WebView2 depois de fechar a aba encontra a view fechada, não
  memória solta.
- **Uma janela filha por painel**, sobre a superfície do Direct2D: o documento a posiciona a cada
  quadro; painel não desenhado e overlay (paleta, menu) por cima escondem a página. O alvo do
  DirectComposition deixou de ser topmost para a janela filha aparecer.
- **Mídia (revê o ADR 0012):** imagem parada nativa (WIC para um bitmap do Direct2D, com zoom e
  arrasto); GIF, SVG, vídeo, áudio e PDF na página: a pasta do arquivo mapeada num host virtual
  (`https://media.cadex.example/`), uma página nossa com `<video>`/`<audio>` com os controles do
  sistema, parado, e o PDF direto no visualizador do Edge (páginas, zoom, Ctrl+F, senha).
- **Markdown renderizado:** a página da nota tem endereço próprio servido pelo app
  (`https://note.cadex.example/<caminho>`, WebResourceRequested), como o `cadex-file:` do Mac:
  imagens relativas resolvem, `#título` rola na página, só arquivos dentro do workspace saem.
  JavaScript desligado e a mesma Content-Security-Policy do Mac.
- **Preview:** InPrivate (dados só enquanto o app está aberto), sem objeto do app na página,
  `file:` recusado, outros esquemas e janela nova para o navegador do sistema.

## Por que não as outras
- Tabelas escritas à mão: o header oficial dá a ordem exata e a licença deixa usar; um método fora
  de ordem só apareceria como crash na VM.
- `WebView2LoaderStatic.lib`: é do MSVC e pede o runtime dele (`_Init_thread_header`, cookie do
  `/GS`, `__guard_dispatch_icall_fptr`); ligar com o lld do Zig exigiria imitar o CRT da Microsoft.
- Achar o runtime direto (registro do EdgeUpdate e a `EmbeddedBrowserWebView.dll`): a função que
  ela exporta não é documentada e muda sem aviso; sem uma máquina para testar, o loader oficial é o
  caminho que a Microsoft mantém. Custa um arquivo de 150 KB ao lado do exe.
- Media Foundation (IMFMediaEngine) e Windows.Data.Pdf: o Windows.Data.Pdf é WinRT, sem ABI
  declarada a partir do Zig (activation factories, HSTRING, IAsyncOperation à mão), e o motor de
  mídia pede controles desenhados por nós e a ponte com a swap chain, nada disso testável sem a
  máquina. O WebView2 já traz player, PDF com busca e senha, e o runtime vem em todo Windows 11.

## Consequências
- Atualizar o SDK é mudar versão e sha256 no script e rodar de novo; arquivo gerado não se edita.
- O instalador do Windows (plano 13) leva o `WebView2Loader.dll` junto do `Cadex.exe`.
- Tudo que é web roda no processo do Edge: memória por painel aberto, e a primeira abertura espera
  o ambiente subir. Vídeo sem codec no runtime (HEVC) mostra o erro, não tela preta.
- A página é uma janela filha: nada do Direct2D desenha por cima dela; o app esconde a página
  enquanto algo precisa ficar em cima. Atalhos do app com a página focada chegam pelo
  AcceleratorKeyPressed; os de edição (copiar, colar, buscar) ficam com a página.
- Não propor trocar o PDF e o player por Media Foundation/Windows.Data.Pdf sem a VM provar que vale.

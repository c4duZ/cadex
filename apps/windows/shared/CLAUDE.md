# apps/windows/shared — compartilhado do app Windows

## O que eu quero
- Só o que 2 ou mais features do app usam: o SDK do Windows, o desenho e a camada de interface.

## O que eu não quero
- Pacote de bindings de terceiros (zigwin32) (`../../../docs/adr/0012-windows-zig-win32-d3d11.md`).
- Tabela COM escrita à mão quando o header do mingw tem a interface: a ordem dos métodos vem dele.
- Método COM que devolve struct por valor (GetSize do D2D): a declaração em C não bate com a ABI.

## Como eu quero
- `win32/sdk.h`: os headers do Windows que o app usa, traduzidos pelo `../build.zig` no módulo
  `sdk`. Header novo entra ali antes de usar a API dele, e a DLL dela no `system_libs` do build.
- `win32/win32.zig` é o módulo `win32`: `c` (o SDK), `L` para literais UTF-16, `call` para chamar
  um método COM pelo nome, `release`, `query`, `check` para HRESULT, os ids de interface que o app
  pede (`iid`, tirados dos headers, porque a libuuid não vem com o Zig) e os cursores padrão.
- `win32/dcomp.zig`: DirectComposition, que o mingw só declara em C++: Device, Target e Visual,
  com as posições da tabela contadas no header. O alvo não é topmost, para as janelas filhas do
  WebView2 aparecerem sobre a superfície.
- `win32/color_dialog.zig`: o seletor de cor do Windows (ChooseColorW), declarado à mão porque o
  commdlg.h não traduz em C com CINTERFACE; a cor de destaque (plano 15) usa.
- `ui/style.zig`: o Style de todo widget: as cores do tema (com `tab_active_text`, o texto que lê
  sobre a aba ativa), `scale` (DPI × zoom da interface), `window_scale` (só o DPI, para o terminal e
  o código do editor), `density` (0,85 no compacto; `rowPx` para alturas de linha e barra) e a fonte
  da interface com o tamanho base (plano 15, fase D). `ui/context.zig`: Ui; `mouse_clip` tira o
  mouse do que uma página rolada deixou fora da vista.
- `strings/` é o módulo `strings` (`../../../docs/adr/0015-english-default-two-languages.md`): `t(en,
  pt)` dá o texto no idioma da interface, o `language` que o app define ao abrir, e `counterpart`
  o do outro idioma, para a paleta achar pelos dois títulos.
- `icons/` é o módulo `icons`: `icons/phosphor.zig` (gerado do Icon.swift do Mac), a fonte do Mac
  embutida, o ícone e a cor por tipo de arquivo, e `icons/material.zig`, os desenhos do Material
  Icon Theme por nome de arquivo e de pasta (ADR 0011), dos PNGs e da tabela
  `icons/file_icons.zig` gerados por `../../../tools/icons/windows_file_icons.py` (não editar).
  `gfx/painter.zig` desenha o PNG (Painter.png) e guarda o bitmap.
- `webview/` é o módulo `webview` (`../../../docs/adr/0014-webview2-on-windows.md`): páginas web em
  painéis, para preview, Markdown renderizado e mídia. `webview/sdk/` é gerado por
  `../../../tools/webview2_sdk.py` (não editar): as tabelas do WebView2.h que o app usa, os ids
  e o WebView2Loader.dll por arquitetura, que o build põe ao lado do exe.
  `webview/environment.zig`: Environment (um por janela, criado assíncrono, perfil em
  %LOCALAPPDATA%\Cadex\WebView2), Host (wake, is_shortcut), `endFrame` esconde o que não foi
  desenhado, `parentMoved`. `webview/view.zig`: View, uma página (InPrivate, scripts, links web ou
  roteados, servidor próprio, pasta mapeada), guarda o que se pede antes de existir; o documento
  chama `show` a cada quadro e lê os eventos com `poll`. `webview/handlers.zig`: os eventos, só
  registrados e enfileirados dentro do retorno do WebView2 (nunca fecham painel ali), nos tipos de
  `webview/events.zig` (Event, Page).
  `webview/com.zig`: handler COM a partir da tabela traduzida, com as referências do dono.
  `webview/resources.zig`: respostas do servidor próprio. `webview/urls.zig`: caminho do Windows
  como endereço e de volta. `webview/loader.zig` e `webview/errors.zig`: o loader e as mensagens.

## Como validar
- `make windows-app` compila; uma declaração errada aparece como erro de tipo ou de link.

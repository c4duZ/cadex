# tools — verificações do repositório

## O que eu quero
- Checagens que transformam regras do repositório em falha de verdade.
- Geradores de dados embutidos no app, com as fontes deles, para a conversão poder ser refeita.

## O que eu não quero
- Script avulso esquecido aqui: script de uso único é apagado depois de rodar.

## Como eu quero
- Python 3 da biblioteca padrão, sem dependências. Cada checagem roda pelo Makefile.
- `check_manifests.py`: as quatro seções, os caminhos citados e um `CLAUDE.md` em toda pasta de
  feature do núcleo e dos apps.
- `themes/build_catalog.py`: gera o catálogo de temas do app a partir dos temas do tweakcn (commit
  fixado no script; o arquivo de entrada é passado na linha de comando) e de
  `themes/official-palettes.json` (paletas oficiais, cada cor com a fonte). Cortes de temas
  parecidos e o padrão ficam no script; descrições em `themes/descriptions.json`; licenças em
  `themes/licenses/` e no `NOTICE`.
- `icons/build_file_icons.py`: gera os ícones de arquivo e pasta do app a partir do Material Icon
  Theme (commit fixado no script; o checkout é passado na linha de comando), com
  `icons/svg_to_pdf.swift` convertendo para PDF. A lista do que entra fica no script
  (`docs/adr/0011-material-file-icons.md`).
- `icons/windows_file_icons.py`: os mesmos ícones Material para o app Windows, a partir dos PDFs
  e do map.json do Mac: PNGs de 32 e 64 px (`icons/pdf_to_png.swift`) e a tabela
  `../apps/windows/shared/icons/file_icons.zig`; `--check` (no `make manifests`) confere que a
  tabela bate com o map.json. Rodar de novo depois do build_file_icons.py.
- `check_command_parity.py` (no `make manifests`): todo id de comando do Mac existe no app Windows
  (ADR 0005, os mesmos ids nos dois). Nome de interface que não é comando vai em NOT_COMMANDS.
- `webview2_sdk.py`: baixa o pacote Microsoft.Web.WebView2 (versão e sha256 fixados no script) e
  gera `../apps/windows/shared/webview/sdk/` (as declarações em C das interfaces que o app usa, os
  ids e o WebView2Loader.dll por arquitetura) (`../docs/adr/0014-webview2-on-windows.md`). Só roda
  de novo para trocar de versão.

## Como validar
- `make manifests` passa.

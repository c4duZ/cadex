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
- `themes/build_catalog.py`: gera o catálogo de temas do app a partir de
  `themes/official-palettes.json` (paletas oficiais, cada cor com a fonte), dos temas do tweakcn
  (`themes/tweakcn.py`, ANSI tirado das cores de cada um) e dos esquemas base16/base24 do
  tinted-theming (`themes/tinted.py`); os commits ficam fixados no script e os dois checkouts são
  passados na linha de comando (`../docs/adr/0017-base16-themes.md`). Contraste conferido e ajustado
  em OKLCH por `themes/colors.py`; quase iguais e recusados saem na saída. Descrições em par
  inglês/português em `themes/descriptions.json`; licenças em `themes/licenses/` e no `NOTICE`.
- `icons/build_file_icons.py`: gera os ícones de arquivo e pasta do app a partir do Material Icon
  Theme (commit fixado no script; o checkout é passado na linha de comando), com
  `icons/svg_to_pdf.swift` convertendo para PDF. A lista do que entra fica no script
  (`docs/adr/0011-material-file-icons.md`).
- `icons/windows_file_icons.py`: os mesmos ícones Material para o app Windows, a partir dos PDFs
  e do map.json do Mac: PNGs de 32 e 64 px (`icons/pdf_to_png.swift`) e a tabela
  `../apps/windows/shared/icons/file_icons.zig`; `--check` (no `make manifests`) confere que a
  tabela bate com o map.json. Rodar de novo depois do build_file_icons.py.
- `icons/build_provider_logos.py`: os logos dos provedores de IA (Lobe Icons e Simple Icons, versões
  fixadas) em PDF para o app (`../docs/adr/0020-provider-logos.md`).
- `check_command_parity.py` (no `make manifests`): todo id de comando do Mac existe no app Windows
  (ADR 0005, os mesmos ids nos dois). Nome de interface que não é comando vai em NOT_COMMANDS.
- `perf/run.py` (`make perf`, depois do `make package`): o orçamento de peso do Cadex no Mac. Abre o
  app de release em instâncias de teste (CADEX_BACKGROUND=1, spaces num arquivo temporário) com o
  "shell" `perf/loadshell.sh` rodando uma carga (e, nos cenários do plano 15, settings.json próprio:
  trocar de tema 300 vezes depois de aquecer, e o jorro com contraste mínimo e ligaduras; no plano 17,
  a conversa de um subagente de 34 MB aberta e fechada pelo CADEX_PERF_SUBAGENT_LOG), e mede memória (footprint) e CPU (tempo de CPU
  gasto na janela, não o %cpu do ps); os índices pela API C com `perf/index_probe.c`. Os limites
  ficam no topo do script, cada um com o que foi medido ao lado.
- `webview2_sdk.py`: baixa o pacote Microsoft.Web.WebView2 (versão e sha256 fixados no script) e
  gera `../apps/windows/shared/webview/sdk/` (as declarações em C das interfaces que o app usa, os
  ids e o WebView2Loader.dll por arquitetura) (`../docs/adr/0014-webview2-on-windows.md`). Só roda
  de novo para trocar de versão.

## Como validar
- `make manifests` passa.

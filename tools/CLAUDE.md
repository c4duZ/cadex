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
- `check_design_tokens.py` (no `make manifests`): os mockups da moldura nova
  (`../docs/design/work-frame/`) e o `../docs/design/work-frame/tokens.json` dela concordam nos dois sentidos (todo valor dos
  mockups é token, todo token aparece num mockup), toda peça citada existe e toda peça está num dos
  planos 25 a 30 (`../docs/adr/0035-work-frame.md`). O que é exemplo fica entre
  `<!-- tokens:off: motivo -->` e `<!-- tokens:on -->`.
- `check_command_parity.py` (no `make manifests`), com os prefixos das features (worktrees,
  agent-tools e computer-use entraram em 2026-11-15; antes não eram conferidos): todo id de comando do Mac existe no app Windows
  (ADR 0005, os mesmos ids nos dois). Nome de interface que não é comando vai em NOT_COMMANDS.
- `perf/run.py` (`make perf`, depois do `make package`): o orçamento de peso do Cadex no Mac. Abre o
  app de release em instâncias de teste (CADEX_BACKGROUND=1, spaces num arquivo temporário) com o
  "shell" `perf/loadshell.sh` rodando uma carga (e, nos cenários do plano 15, settings.json próprio:
  trocar de tema 300 vezes depois de aquecer, e o jorro com contraste mínimo e ligaduras; no plano 17,
  a conversa de um subagente de 34 MB aberta e fechada pelo CADEX_PERF_SUBAGENT_LOG, cinco abas de
  terminal a mais pelo CADEX_PERF_TABS e tudo da barra lateral e da barra de status ligado, com contas,
  sessões e hosts de teste pelo CADEX_PERF_HOME, no máximo 10% acima do parado; no plano 18, três
  contas (uma gerenciada, com links) e 200 conversas pelo CADEX_PERF_HOME, com a página History aberta e
  fechada, no máximo 10% acima do parado, e fechada nem o arquivo do índice nasce; no plano 19, em
  `perf/plan19.py`, dez terminais mantidos pelo daemon com a janela e com o app morto (os dez shells
  continuam, e fechados os dez o daemon sai do `ps`) e cinco sessões mandando hooks a cada segundo, e com a opção desligada nenhum daemon; no plano 20, em `perf/plan20.py`, as ferramentas do agente desligadas (pedido recusado, memória do parado) e um agente falso (`perf/plan20_agent.py`, a carga `agent` do loadshell) que dirige o preview pelo socket do app, 100 snapshots e 100 cliques; no plano 21, em `perf/plan21.py`, a revisão de uma worktree falsa de 50 arquivos aberta pelo CADEX_PERF_REVIEW e rolada, com 20 comentários e 200 edições pelo socket, e a autoria desligada; no plano 22, em `perf/plan22.py` (com `perf/plan22_engine.py`), o `cadex-memory` do pacote numa pasta temporária, com HOME temporária: parado com uma sessão, com o modelo de vetores carregado por 500 páginas e 10 buscas e de volta ao parado depois de descarregar e se reiniciar, e uma wiki de 2 mil páginas com uma sessão falsa de 500 eventos (hook e briefing pelo socket, o `cadex memory-hook` inteiro), e o app parado sem nenhum `cadex-memory` no `ps`; o modelo vem de CADEX_PERF_MODELS ou o engine o baixa; no plano 23, em `perf/plan23.py`, um daemon do Tailscale falso (LocalAPI num socket Unix, 20 máquinas) que o app de teste acha pelo CADEX_PERF_TAILSCALE_SOCKET, o grupo do cartão do ssh aberto duas vezes pelo CADEX_PERF_MACHINES (a primeira abertura à parte), e com machines.tailscale desligada nenhum pedido ao daemon; no plano 24, em `perf/plan24.py`, corridas e execuções desligadas (o peso do parado, nenhum arquivo de estado, nenhum LaunchAgent nem job no launchd) e ligadas com agentes falsos (`perf/fake_claude.py`, pelo CADEX_CLAUDE_BIN: lê o `--settings` do kit, manda os hooks e o OSC 7501, reporta pelo `cadex run`, nunca a rede), uma corrida de 3 e uma execução de 5 tarefas pelo CADEX_PERF_RACE e CADEX_PERF_RUN, numa conta falsa que confia no repositório de teste: memória, CPU, todos os agentes de pé, a cadeia concluída, e nenhuma conexão de rede nem arquivo do Keychain abertos (`lsof`);
  cada instância de teste tem os próprios sockets e tokens, CADEX_SOCKETS_DIR, CADEX_SESSIONS_DIR e
  CADEX_TERMINAL_SOCKET, e nunca toca os do dono; os gatilhos ficam em `../apps/macos/app/PerfHooks.swift`), e mede memória (footprint) e CPU (tempo de CPU
  gasto na janela, não o %cpu do ps); os índices pela API C com `perf/index_probe.c`. Os limites
  ficam em `perf/limits.py`, cada um com o que foi medido ao lado.
- `memory_eval.py` (`make memory-eval MODELS=<pasta>`): a busca da memória medida, as ADRs e specs
  como páginas e 30 perguntas, só por palavra contra a híbrida (plano 22 fase D; o resultado fica em
  `../docs/spec/memory.md`).
- `webview2_sdk.py`: baixa o pacote Microsoft.Web.WebView2 (versão e sha256 fixados no script) e
  gera `../apps/windows/shared/webview/sdk/` (as declarações em C das interfaces que o app usa, os
  ids e o WebView2Loader.dll por arquitetura) (`../docs/adr/0014-webview2-on-windows.md`). Só roda
  de novo para trocar de versão.

## Como validar
- `make manifests` passa.

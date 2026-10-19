# Plano 4 — Arquivos: workspace, explorer e busca

Depende de: planos 2 e 3 · Features: workspace, explorer, search (núcleo e app) · Specs a escrever:
workspace, explorer, search.

## O que eu quero
- **Workspace:** a pasta raiz aberta. Definida ao abrir o app com uma pasta (`cadex .` ou arrastar a
  pasta no ícone), pela paleta ("Abrir pasta…") ou seguindo a pasta do terminal ativo. O núcleo só
  lê, escreve ou abre processos dentro de diretórios autorizados.
- **Explorer** no painel lateral: árvore carregada sob demanda, ícones por tipo de arquivo, arquivos
  ocultos alternáveis, marcação de arquivos alterados no git (quando o plano 6 existir), navegação por
  teclado, renomear inline, criar arquivo e pasta, mover arrastando, apagar para a Lixeira, revelar no
  Finder, copiar caminho, abrir no terminal (`cd`), arrastar para o terminal (cola o caminho).
  Atualiza sozinho quando o disco muda.
- **Busca:** paleta em modo "arquivos" (⌘P) com busca fuzzy de nomes, rápida a cada tecla; modo
  "conteúdo" (⌘Shift+F) com busca de texto e regex no workspace, resultados aparecendo aos poucos,
  respeitando .gitignore, .ignore e ocultos; abrir o resultado na linha (visualizador do plano 5;
  até lá, no editor padrão do sistema).

## O que eu não quero
- Operação de arquivo fora de diretório autorizado, inclusive por link simbólico ou `../`.
- Ler a árvore inteira de uma vez ou o conteúdo de arquivos grandes sem limite.
- Busca que trava a digitação ou não cancela quando a consulta muda.
- Apagar de verdade sem passar pela Lixeira.
- Ícones de terceiros sem licença compatível registrada no `NOTICE`.

## Como eu quero
**Onde estamos.** O painel lateral existe e está vazio (plano 3). A paleta e o fuzzy de pontuação
existem (plano 2, função fuzzy em core/features/search). As pastas das features já têm manifestos:
`core/features/workspace/CLAUDE.md`, `core/features/explorer/CLAUDE.md`,
`core/features/search/CLAUDE.md`, `apps/macos/features/explorer/CLAUDE.md`,
`apps/macos/features/search/CLAUDE.md`. A API C segue as convenções de `core/include/cadex.h`
(prefixo por feature, status, cadex_free); cada feature exporta pelo próprio c_api.zig, importado em
`core/cadex.zig`.

**Fases:**
- **A. Workspace (núcleo):** registro de diretórios autorizados com caminhos canonicalizados
  (realpath) antes de comparar; diretório de lançamento pelo argumento de linha de comando; API C
  autorizar, consultar, autorizar-a-pasta-do-terminal. Comando `cadex` no terminal fica fora do MVP
  (ADR 0007); abrir pasta pela paleta e pelo Dock entra.
- **B. Explorer (núcleo):** listar pasta (nome, tipo, tamanho, ignorado pelo git), criar, renomear,
  mover, copiar, apagar para a Lixeira (no app, via NSWorkspace/FileManager.trashItem, já que a
  Lixeira é do sistema), ler arquivo com detecção de binário e limite de tamanho; observação de
  pastas com FSEvents (macOS) agregando eventos e avisando o app por callback (mesmo padrão de
  thread e de callback de `core/features/terminal/session.zig`).
- **C. Explorer (app):** NSOutlineView com carregamento sob demanda, ícones (SF Symbols ou conjunto
  com licença MIT/Apache), menu de contexto com comandos registrados, arrastar para o terminal
  reaproveitando o escapador de caminhos do plano 1.
- **D. Busca (núcleo):** índice de nomes em memória atualizado pela observação de arquivos; parser de
  .gitignore (padrões, negação, pastas, aninhados); busca de conteúdo numa thread com cancelamento e
  resultados em lotes por callback; regex: decidir em ADR (biblioteca C madura como PCRE2, BSD, ou
  só texto literal no MVP).
- **E. Busca (app):** modos da paleta ⌘P e ⌘Shift+F; resultados com trecho e número da linha;
  abrir no ponto certo.

## Como validar
- `make check` passa ao fim de cada fase.
- Testes do núcleo com pastas temporárias: recusa fora do workspace (link simbólico, `../`);
  criar/renomear/mover; observação avisa criação e remoção; .gitignore com negação e pasta aninhada;
  busca cancelada não entrega resultados velhos; fuzzy acha "cntrl" em "core/features/terminal/c_api".
- Manual, com print: abrir a pasta do Cadex, expandir `core/features/`, renomear, apagar para a
  Lixeira, arrastar um arquivo para o terminal, ⌘P achando render.zig, ⌘Shift+F achando
  "libghostty" e abrindo na linha.
- Atualizar specs, `CLAUDE.md` das features e o status em `docs/plans/README.md`.

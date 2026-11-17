# Cadex

Workspace de desenvolvimento centrado no terminal, nativo e escrito do zero.

## O que eu quero
- **Trabalho em andamento:** seguir `docs/plans/README.md` (planos do fim do terminal até o MVP no
  Mac, em ordem). Começar uma sessão lendo este arquivo, o índice e o plano da vez.
- Código próprio, licença MIT.
- O app mais leve e rápido possível em cada sistema: macOS primeiro, Windows depois, sobre o mesmo
  núcleo.
- Instalar em um passo: um comando (`curl ... | sh`) ou o DMG, sem dependências
  (`docs/adr/0007-one-step-install.md`).
- Tudo pode ser feito pelo ⌘K: toda ação do app é um comando que a paleta encontra e executa
  (`docs/adr/0005-every-action-is-a-command.md`).
- As features abaixo, cada uma com pasta própria e o mesmo nome no núcleo e no app:

| feature | núcleo | app macOS | o que faz |
|---|---|---|---|
| terminal | sim | sim | sessões PTY, modelo libghostty-vt, render Metal, teclado, colagem, busca, o daemon que mantém as sessões |
| explorer | sim | sim | operações de arquivo, observação do disco, árvore e ícones |
| search | sim | sim | busca de arquivo por nome (fuzzy) e de conteúdo, respeitando .gitignore |
| source-control | sim | sim | status, diff, stage, commit, push e pull via o binário git |
| git-history | sim | sim | log de commits e grafo |
| worktrees | sim | sim | worktree por tarefa: New Task, status e comentário, hooks de preparo |
| workspace | sim | não | diretórios autorizados, diretório de lançamento, ambiente (WSL no Windows) |
| editor | sim | sim | ler código: números de linha, dobrar, destaque de sintaxe (tree-sitter), linha atual |
| preview | não | sim | preview web de servidores locais e URLs; escolher elemento para o agente |
| media-preview | não | sim | imagem, vídeo, áudio e PDF com os frameworks do sistema |
| markdown | sim | sim | Markdown renderizado; ao editar: autocomplete de link, ⌘+clique, links quebrados, quem aponta pra cá |
| tabs | não | sim | abas e divisões de painel |
| sidebar | não | sim | a árvore do trabalho à esquerda: projetos, terminais e tarefas (a fileira de ícones sai no plano 27) |
| inspector | não | sim | o painel da seleção à direita: Changes, Files, History e Memory (plano 26) |
| home | não | sim | a tela de início: o pedido, os cartões Terminal, Agent, Task e Race, os projetos recentes (plano 29) |
| agents | não | sim | as sessões de agente nas contas do Claude Code: lidas, o quadro do que precisa de você, hibernar |
| agent-tools | sim | sim | o programa `cadex` que as sessões abertas pelo Cadex rodam (status line, hooks) e o socket do app |
| memory | sim | sim | a memória do projeto entre sessões, contas e agentes: o engine do ai-memory no processo `cadex-memory`, briefing, busca, página Memory |
| orchestration | não | sim | vários agentes de uma vez: a mesma tarefa em N agentes, execuções com tarefas despachadas, automações agendadas |
| review | não | sim | comentários na revisão de uma tarefa, mandados ao agente dela num texto só |
| computer-use | não | sim | o agente opera outros apps do Mac pela acessibilidade, com permissão do dono por app |
| ssh | não | sim | os hosts do ~/.ssh/config, se respondem, e conectar numa aba |
| machines | não | sim | as máquinas da tailnet pelo Tailscale do dono: online, caminho, latência, conectar; depois "Rodar em", Docker e compartilhar |
| projects | não | sim | o projeto: a pasta de um repositório com as abas abertas nela, restaurado entre sessões (o que eram os spaces, plano 27) |
| themes | não | sim | temas do app e do editor, imagem de fundo |
| settings | não | sim | janela de configurações e preferências salvas |
| command-palette | não | sim | ⌘K: registro de todos os comandos e a paleta que executa qualquer um |
| shortcuts | não | sim | atalhos configuráveis |
| status-bar | não | sim | barra de status |
| power | não | sim | manter o computador acordado, sempre ou com programa rodando |
| updates | não | sim | procurar versão nova e atualizar o app com um clique |

## O que eu não quero
- Código de outro app copiado, traduzido ou aberto como referência. A referência é o comportamento em
  `docs/spec/`. Ver `docs/adr/0004-clean-rewrite.md`. Exceção única: o engine da memória é o fork do
  ai-memory, sem edição nos crates dele (`docs/adr/0028-project-memory.md`).
- WebView, Electron ou Tauri para a interface (`docs/adr/0001-macos-first-native-app.md`).
- IA embutida no app. O Cadex não roda modelo nem guarda chave: quando a memória precisa de IA, quem
  pensa é o Claude Code do usuário, na sessão ou numa sessão nova pelo CLI na mesma conta
  (`docs/adr/0028-project-memory.md`). Agentes de código rodam numa aba de terminal; o Cadex observa
  as sessões e o uso deles e, num clique numa conta, digita o comando que abre o agente dela
  (`docs/adr/0019-agents-observe-only.md`).
- Modo em blocos e terminal privado ficaram de fora. Agentes rodam em abas de terminal; o Cadex os
  abre com prompt quando o dono escreve o pedido (tela de início, Nova tarefa) ou liga corrida,
  orquestração, automação ou o agente de memória (ligado por padrão), sempre com teto no que roda
  sem ele (`docs/adr/0033-cadex-launches-agents.md`, `docs/adr/0036-owner-words-reach-the-agent.md`,
  `docs/adr/0029-memory-agent.md`, `docs/adr/0037-memory-agent-on-by-default.md`).
- Ação que não é um comando registrado (que só existe num botão, menu ou atalho).
- Feature importando o miolo de outra feature.
- Swift chamando detalhe interno do Zig, ou qualquer código falando com a libghostty fora da feature
  `terminal` do núcleo.
- Dependência nova sem motivo, e arquivo acima de 500 linhas.

## Como eu quero
- `core/`: núcleo em Zig, exposto por uma API C (`docs/adr/0002-zig-core-with-c-api.md`). O engine
  da memória é Rust, num executável à parte (`docs/adr/0028-project-memory.md`).
  `apps/macos/`: Swift com AppKit e Metal. `apps/windows/`: Zig com Win32 e
  Direct3D 11, Windows 11 (`docs/adr/0012-windows-zig-win32-d3d11.md`).
- Toda ação é um comando registrado na feature `command-palette`; menus, botões e atalhos só
  disparam comandos pelo id.
- O que 2+ features usam sobe para `core/shared/` ou `apps/macos/shared/`. Só isso vai para lá.
- Feature nova: spec em `docs/spec/<feature>.md` antes do código, pasta própria com `CLAUDE.md`
  neste formato, testes dentro, uma linha na tabela acima.
- Código e identificadores em inglês; manifestos, specs e ADRs em português.
- Arquivos de 200 a 300 linhas, funções curtas, nomes únicos e fáceis de achar no grep.
- Comentário explica o porquê, com a origem (bug, medição, data).
- Componente de terceiros entra no `NOTICE` na mesma tarefa que o adiciona.
- Ícones: Phosphor em todo o app, pela fonte de ícones em `apps/macos/shared/icons/`
  (`docs/adr/0008-phosphor-icons.md`). Nada de SF Symbols. Exceção: ícones de tipo de arquivo e
  pasta do Material Icon Theme (`docs/adr/0011-material-file-icons.md`) e logos dos provedores de IA
  numa conta (`docs/adr/0020-provider-logos.md`).
- Ao mudar ponto de entrada, regra ou comando de uma feature, atualize o `CLAUDE.md` dela junto.
- Termo novo do domínio entra em `docs/CONTEXT.md`. Decisão que alguém proporia desfazer vira ADR.

## Como validar
- `make check` antes de entregar: manifestos, testes do núcleo e do engine da memória, testes do app macOS e o build do
  app Windows (compila daqui; roda só na VM, com `make windows-core-test` e `make windows-run`).
- `make manifests`: todo `CLAUDE.md` tem as quatro seções e todo caminho citado entre crases existe
  (`tools/check_manifests.py`).
- `make core-test`: `zig build test` com o alocador de teste (pega vazamento de memória).
- `make memory-test`: os testes do engine da memória (`cargo test`, com o Rust do `rustup`); a suíte
  do upstream roda no PC a cada atualização dele (`make memory-upstream-test`).
- `make macos-test`: `swift test` do app.
- `make perf`: o orçamento de peso (`tools/perf/run.py`), antes de cada release e de cada feature que
  mexe em terminal, índices, árvore ou desenho: o app de release e os índices nas situações que já o
  deixaram pesado (terminal jorrando, TUI, pasta pessoal, agente salvando arquivos); falha acima do
  limite. Limite só sobe com o motivo escrito ao lado.

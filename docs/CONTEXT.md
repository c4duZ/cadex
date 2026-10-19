# Vocabulário do Cadex

Os termos que aparecem em conversa, spec e código, e o que significam aqui. Termo novo que surgir
numa conversa entra nesta lista. Entre parênteses, o nome usado no código.

## Estrutura do app
- **Núcleo** (`core`): biblioteca em Zig com a lógica que não depende de plataforma, exposta por uma
  API C.
- **App** (`apps/macos`, `apps/windows`): a interface nativa de cada sistema. Desenha, recebe
  entrada e chama o núcleo.
- **Feature**: um assunto do produto (terminal, explorer, source-control...). Tem pasta própria no
  núcleo e/ou no app, com o mesmo nome.
- **Porta de entrada**: a parte pública de uma feature. As outras features só usam isso.
- **Spec**: a descrição do comportamento de uma feature em `docs/spec/`. É a referência da reescrita.

## Janela e layout
- **Space** (`space`): um grupo de abas com nome, que o usuário alterna. Restaurado entre sessões.
- **Aba** (`tab`): um item da barra de abas. Pode ser terminal, editor, preview, markdown, mídia,
  diff ou histórico do git.
- **Painel** (`pane`): uma divisão dentro de uma aba de terminal. Uma aba pode ter vários painéis.
- **Folha** (`leaf`): um painel final da árvore de divisões, que contém uma sessão de terminal.
- **Barra lateral** (`sidebar`): a coluna com o explorer ou o source control.
- **Barra de status** (`status-bar`): a faixa inferior com diretório, ambiente e diagnósticos.
- **Paleta de comandos** (`command-palette`): a busca de ações e arquivos por teclado.

## Terminal
- **Sessão** (`session`): um shell rodando num PTY, ligado a uma folha.
- **PTY**: o pseudo-terminal do sistema por onde o shell lê e escreve.
- **Modelo do terminal** (`terminal model`): o estado da tela (grade, cursor, scrollback, modos),
  mantido pela libghostty-vt.
- **Render** (`renderer`): a parte que desenha a grade na tela (Metal no macOS).
- **Scrollback**: as linhas que já saíram do topo da tela e ainda podem ser vistas rolando.
- **Modo em blocos** (`blocks`): terminal em que cada comando e sua saída viram um bloco, com um
  campo de comando separado, estilo editor.
- **Bloco** (`block`): um comando executado e a saída dele, no modo em blocos.
- **Integração de shell** (`shell integration`): o script injetado no shell que avisa o diretório
  atual e onde começa e termina cada comando (OSC 7 e OSC 133).
- **Bracketed paste**: modo em que o programa pede que o texto colado venha marcado, para não ser
  executado como digitação.
- **Ambiente** (`workspace environment`): onde os processos rodam. Local, ou uma distro WSL no
  Windows.

## Arquivos e projeto
- **Workspace**: a pasta raiz aberta, que o explorer mostra e a busca percorre.
- **Diretório autorizado**: pasta em que o núcleo aceita ler, escrever ou abrir processos. Fora dela,
  a operação é recusada.
- **Diretório de lançamento**: a pasta passada ao abrir o app pela linha de comando.
- **Observação de arquivos** (`file watch`): o aviso do sistema quando algo muda no disco.

## Editor e código
- **Language server** (`LSP`): processo externo que dá diagnósticos, navegação, autocomplete e
  formatação para uma linguagem.
- **Diagnóstico**: erro ou aviso que o language server aponta numa linha.
- **Formatador externo**: programa como Prettier, Ruff ou rustfmt, rodado ao salvar.

## Git
- **Source control**: o painel de stage, commit, push e pull.
- **Stage**: marcar mudanças para entrar no próximo commit.
- **Upstream**: a branch remota que a branch local acompanha.
- **Grafo** (`git graph`): o desenho das linhas de commits e merges no histórico.

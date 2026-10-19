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
- **Barra de status** (`status-bar`): a faixa inferior com diretório e ambiente.
- **Paleta de comandos** (`command-palette`): a busca de ações aberta pelo ⌘K. Executa qualquer comando.
- **Comando** (`command`): uma ação do app, com id, título e a função que executa. Menus, botões e
  atalhos só disparam comandos.

## Terminal
- **Sessão** (`session`): um shell rodando num PTY, ligado a uma folha.
- **PTY**: o pseudo-terminal do sistema por onde o shell lê e escreve.
- **Modelo do terminal** (`terminal model`): o estado da tela (grade, cursor, scrollback, modos),
  mantido pela libghostty-vt.
- **Render** (`renderer`): a parte que desenha a grade na tela (Metal no macOS).
- **Scrollback**: as linhas que já saíram do topo da tela e ainda podem ser vistas rolando.
- **Integração de shell** (`shell integration`): o script injetado no shell que avisa o diretório
  atual (OSC 7).
- **Bracketed paste**: modo em que o programa pede que o texto colado venha marcado, para não ser
  executado como digitação.
- **Diretório autorizado** (`authorized directory`): pasta que o usuário abriu nesta execução. O
  núcleo só mexe em arquivos dentro de uma delas, com o caminho resolvido (sem `..` nem links).
- **Ignorado** (`ignored`): o que .gitignore, .ignore ou .git/info/exclude deixam de fora. Aparece
  apagado no explorer e não entra na busca.
- **Índice de nomes** (`search index`): a lista dos arquivos do workspace em memória, que o ⌘P
  consulta a cada tecla e que acompanha o disco.
- **Ambiente** (`workspace environment`): onde os processos rodam. Local, ou uma distro WSL no
  Windows.

## Arquivos e projeto
- **Workspace**: a pasta raiz aberta, que o explorer mostra e a busca percorre.
- **Diretório autorizado**: pasta em que o núcleo aceita ler, escrever ou abrir processos. Fora dela,
  a operação é recusada.
- **Diretório de lançamento**: a pasta passada ao abrir o app pela linha de comando.
- **Observação de arquivos** (`file watch`): o aviso do sistema quando algo muda no disco.

## Editor e código
- **Destaque de sintaxe** (`syntax highlighting`): as cores por tipo de trecho (string, palavra-chave,
  comentário), calculadas pelo tree-sitter.
- **Dobrar** (`folding`): esconder e mostrar um bloco de código pela setinha ao lado do número da
  linha.
- **tree-sitter**: biblioteca em C que entende a estrutura do código de cada linguagem; dá o destaque
  de sintaxe e as regiões que podem ser dobradas.
- **Link wiki** (`[[nota]]`): link para outro Markdown pelo nome do arquivo, sem caminho nem extensão.
- **Quem aponta pra cá** (`backlinks`): os arquivos Markdown que têm link para o arquivo aberto.
- **Link quebrado**: link para arquivo ou título que não existe; aparece sublinhado.

## Git
- **Source control**: o painel de stage, commit, push e pull.
- **Stage**: marcar mudanças para entrar no próximo commit.
- **Upstream**: a branch remota que a branch local acompanha.
- **Grafo** (`git graph`): o desenho das linhas de commits e merges no histórico.

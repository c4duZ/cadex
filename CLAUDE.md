# Cadex

Workspace de desenvolvimento centrado no terminal, nativo e escrito do zero.

## O que eu quero
- Recriar todas as funcionalidades do Terax com código próprio, licença MIT.
- O app mais leve e rápido possível em cada sistema: macOS primeiro, Windows depois, sobre o mesmo
  núcleo.
- As features abaixo, cada uma com pasta própria e o mesmo nome no núcleo e no app:

| feature | núcleo | app macOS | o que faz |
|---|---|---|---|
| terminal | sim | sim | sessões PTY, modelo libghostty-vt, render Metal, teclado, colagem, modo em blocos |
| explorer | sim | sim | operações de arquivo, observação do disco, árvore e ícones |
| search | sim | sim | busca de arquivo por nome (fuzzy) e de conteúdo, respeitando .gitignore |
| source-control | sim | sim | status, diff, stage, commit, push e pull via o binário git |
| git-history | sim | sim | log de commits e grafo |
| language-server | sim | sim | processos LSP e integração com o editor |
| command-history | sim | sim | histórico e sugestões de comandos do terminal |
| workspace | sim | não | diretórios autorizados, diretório de lançamento, ambiente (WSL no Windows) |
| editor | não | sim | editor de código, vim, formatar ao salvar |
| preview | não | sim | preview web de servidores locais e URLs |
| media-preview | não | sim | imagem, vídeo, áudio e PDF com os frameworks do sistema |
| markdown | não | sim | Markdown renderizado |
| tabs | não | sim | abas e divisões de painel |
| spaces | não | sim | grupos de abas restaurados entre sessões |
| themes | não | sim | temas do app e do editor, imagem de fundo |
| settings | não | sim | janela de configurações e preferências salvas |
| command-palette | não | sim | paleta de comandos |
| shortcuts | não | sim | atalhos configuráveis |
| status-bar | não | sim | barra de status |

## O que eu não quero
- Código do Terax copiado, traduzido ou aberto como referência. A referência é o comportamento em
  `docs/spec/`. Ver `docs/adr/0004-clean-rewrite.md`.
- WebView, Electron ou Tauri para a interface (`docs/adr/0001-macos-first-native-app.md`).
- IA embutida no app. Agentes de código rodam numa aba de terminal.
- Feature importando o miolo de outra feature.
- Swift chamando detalhe interno do Zig, ou qualquer código falando com a libghostty fora da feature
  `terminal` do núcleo.
- Dependência nova sem motivo, e arquivo acima de 500 linhas.

## Como eu quero
- `core/`: núcleo em Zig, exposto por uma API C (`docs/adr/0002-zig-core-with-c-api.md`).
  `apps/macos/`: Swift com AppKit e Metal. `apps/windows/`: reservado.
- O que 2+ features usam sobe para `core/shared/` ou `apps/macos/shared/`. Só isso vai para lá.
- Feature nova: spec em `docs/spec/<feature>.md` antes do código, pasta própria com `CLAUDE.md`
  neste formato, testes dentro, uma linha na tabela acima.
- Código e identificadores em inglês; manifestos, specs e ADRs em português.
- Arquivos de 200 a 300 linhas, funções curtas, nomes únicos e fáceis de achar no grep.
- Comentário explica o porquê, com a origem (bug, medição, data).
- Componente de terceiros entra no `NOTICE` na mesma tarefa que o adiciona.
- Ao mudar ponto de entrada, regra ou comando de uma feature, atualize o `CLAUDE.md` dela junto.
- Termo novo do domínio entra em `docs/CONTEXT.md`. Decisão que alguém proporia desfazer vira ADR.

## Como validar
- `make check` antes de entregar: manifestos, testes do núcleo e testes do app.
- `make manifests`: todo `CLAUDE.md` tem as quatro seções e todo caminho citado entre crases existe
  (`tools/check_manifests.py`).
- `make core-test`: `zig build test` com o alocador de teste (pega vazamento de memória).
- `make macos-test`: `swift test` do app.

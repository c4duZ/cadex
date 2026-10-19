# Cadex

Workspace de desenvolvimento centrado no terminal, nativo e escrito do zero.

## O que eu quero
- Recriar todas as funcionalidades do Terax com código próprio, licença MIT.
- O app mais leve e rápido possível em cada sistema: macOS primeiro, Windows depois, sobre o mesmo
  núcleo.
- Tudo pode ser feito pelo ⌘K: toda ação do app é um comando que a paleta encontra e executa
  (`docs/adr/0005-every-action-is-a-command.md`).
- As features abaixo, cada uma com pasta própria e o mesmo nome no núcleo e no app:

| feature | núcleo | app macOS | o que faz |
|---|---|---|---|
| terminal | sim | sim | sessões PTY, modelo libghostty-vt, render Metal, teclado, colagem, busca |
| explorer | sim | sim | operações de arquivo, observação do disco, árvore e ícones |
| search | sim | sim | busca de arquivo por nome (fuzzy) e de conteúdo, respeitando .gitignore |
| source-control | sim | sim | status, diff, stage, commit, push e pull via o binário git |
| git-history | sim | sim | log de commits e grafo |
| workspace | sim | não | diretórios autorizados, diretório de lançamento, ambiente (WSL no Windows) |
| editor | sim | sim | ler código: números de linha, dobrar, destaque de sintaxe (tree-sitter), linha atual |
| preview | não | sim | preview web de servidores locais e URLs |
| media-preview | não | sim | imagem, vídeo, áudio e PDF com os frameworks do sistema |
| markdown | sim | sim | Markdown renderizado; ao editar: autocomplete de link, ⌘+clique, links quebrados, quem aponta pra cá |
| tabs | não | sim | abas e divisões de painel |
| spaces | não | sim | grupos de abas restaurados entre sessões |
| themes | não | sim | temas do app e do editor, imagem de fundo |
| settings | não | sim | janela de configurações e preferências salvas |
| command-palette | não | sim | ⌘K: registro de todos os comandos e a paleta que executa qualquer um |
| shortcuts | não | sim | atalhos configuráveis |
| status-bar | não | sim | barra de status |

## O que eu não quero
- Código do Terax copiado, traduzido ou aberto como referência. A referência é o comportamento em
  `docs/spec/`. Ver `docs/adr/0004-clean-rewrite.md`.
- WebView, Electron ou Tauri para a interface (`docs/adr/0001-macos-first-native-app.md`).
- IA embutida no app. Agentes de código rodam numa aba de terminal.
- Modo em blocos, terminal privado e launcher de agentes: ficaram de fora do Cadex.
- Ação que não é um comando registrado (que só existe num botão, menu ou atalho).
- Feature importando o miolo de outra feature.
- Swift chamando detalhe interno do Zig, ou qualquer código falando com a libghostty fora da feature
  `terminal` do núcleo.
- Dependência nova sem motivo, e arquivo acima de 500 linhas.

## Como eu quero
- `core/`: núcleo em Zig, exposto por uma API C (`docs/adr/0002-zig-core-with-c-api.md`).
  `apps/macos/`: Swift com AppKit e Metal. `apps/windows/`: reservado.
- Toda ação é um comando registrado na feature `command-palette`; menus, botões e atalhos só
  disparam comandos pelo id.
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

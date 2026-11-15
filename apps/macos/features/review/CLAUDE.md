# review (app macOS)

## O que eu quero
- Comentar em qualquer linha ou intervalo da revisão de uma tarefa e mandar tudo ao agente dela num
  texto só, de uma vez (`../../../../docs/spec/review.md`, plano 21 fase D).
- Saber quem escreveu cada linha, o agente ou o dono (fase E, `../../../../docs/adr/0027-local-authorship.md`).

## O que eu não quero
- Importar o source-control: a aba de revisão é de lá, e o app liga as duas pela porta de entrada
  de cada uma (as anotações e a seleção de linhas da aba; os comentários daqui).
- Mandar ao agente com Enter: vai colado, sem Enter, e o dono aperta (como o seletor de elementos).

## Como eu quero
- `ReviewComment.swift`: o comentário (arquivo, lado, linhas, o texto delas, 3 linhas em volta, o
  Markdown do dono) e `placed(in:)`, que acha o trecho no arquivo como está agora (o que tem mais
  contexto em comum, depois o mais perto de onde estava) ou o marca desatualizado.
- `ReviewCommentStore.swift`: por worktree em `~/Library/Application Support/Cadex/review/<repo>/<worktree>.json`
  (CADEX_REVIEW_DIR nas instâncias de teste), os pendentes e os enviados, gravado a cada mudança.
- `ReviewComments.swift`: a lista de uma worktree (acrescentar, editar, apagar, recolocar, a
  mensagem na ordem dos arquivos e das linhas, os enviados indo para o histórico, `move` de um
  desatualizado para outras linhas com as mesmas palavras) e
  ReviewCommentText, o texto que o agente lê (o caminho, as linhas, o trecho citado e o comentário).
- `ReviewCommentEditor.swift`: o campo num popover sob as linhas, ⌘↩ salva, esc desiste.
- `ReviewCommentCommands.swift`: review.add-comment (c, só com a revisão em foco), review.edit-comment,
  review.delete-comment, review.send-comments, review.clear-comments e review.show-sent (os enviados
  na paleta; escolher copia de novo), com o que cada um faz dado pelo app
  (`../../app/ReviewCommentsWiring.swift`).
- Autoria (fase E): `ReviewAuthorship.swift`, puro: os intervalos do agente com a sessão, levados
  de uma versão do arquivo para a seguinte pelas linhas que não mudaram (a linha tocada perde a
  marca) e as linhas de uma edição acrescentadas. `ReviewAuthorshipTracker.swift`: uma worktree; a
  edição do agente marca as linhas dele; a mudança no disco sem evento compara com a última versão
  e passa as linhas tocadas ao dono; guarda em `<worktree>-authorship.json` (intervalos, nunca
  texto) e as últimas versões em `<worktree>-versions/` só enquanto a worktree existe, até 2 MB por
  arquivo e 50 MB por worktree (passou, o arquivo para); exportar e esquecer.
  `ReviewAuthorshipCommands.swift`: review.toggle-authorship e review.export-authorship. A ligação:
  `../../app/ReviewAuthorshipWiring.swift`.

## Como validar
- `make macos-test` (`tests/main.swift`): o comentário seguindo as linhas quando o agente acrescenta
  linhas acima, o contexto escolhendo a cópia certa, desatualizado e de volta; a lista sobrevivendo ao
  app (acrescentar, editar, apagar, enviados no histórico) e a mensagem; a ordem dos arquivos.
- `tests/Authorship.swift`: as marcas seguindo as linhas, a edição do agente e depois a do dono,
  o arquivo criado inteiro, guardado sem texto, o arquivo grande parado, exportar e esquecer.
- No app: um comentário numa linha e outro num intervalo chegam ao terminal do agente num texto só.

# review

## Para que serve
Revisar de verdade o que o agente fez numa tarefa sem sair do Cadex: todas as mudanças da worktree
numa aba só, contra o ponto onde a tarefa começou; comentar em qualquer linha e mandar tudo de volta
ao agente de uma vez; ver o que o agente escreveu e o que o dono escreveu (`docs/plans/21-review.md`,
`docs/adr/0027-local-authorship.md`). O diff contra base, o stage parcial, a imagem e o conflito são
do source-control (`source-control.md`); comentários e autoria são desta feature, só no app macOS.

## Comportamento

### A aba de revisão
- Abre por git.review-open (⌘K, o botão no grupo da worktree em Agents e no cabeçalho do Git): uma
  aba por worktree, com o nome da tarefa. Abrir de novo a mesma worktree vai à aba que já existe.
- À esquerda, a árvore dos arquivos mudados (com A, M, D, R e a contagem +/−); à direita, todos os
  arquivos empilhados numa rolagem só, cada um com o cabeçalho (caminho, estado, +/−) e os trechos.
  Clicar na árvore leva ao arquivo.
- **Base:** por padrão, o ponto onde a tarefa saiu do branch de partida (o merge-base entre a worktree
  e o branch gravado pelo New Task, `worktrees.md`); sem branch gravado, o merge-base com a branch
  padrão do repositório. git.review-set-base troca para qualquer commit ou branch; a base em uso
  aparece no topo da aba. git.review-compare-worktrees compara as pontas de duas worktrees.
- Entram as mudanças commitadas desde a base, as staged, as não staged e os arquivos novos.
- Linhas sem mudança são recolhidas (3 de contexto, git.reviewContextLines); "mostrar mais" expande
  aquela região; git.review-toggle-collapse mostra tudo. Numeração dos dois lados, quebra de linha
  (git.review-toggle-wrap, git.reviewWrap) e espaços visíveis (git.review-toggle-whitespace,
  git.reviewShowWhitespace).
- Teclado, com a aba em foco: j / k próximo e anterior arquivo, n / p próximo e anterior trecho,
  c comenta a linha do cursor. Configuráveis em shortcuts, como todo atalho.
- Stage por trecho e por linha direto na aba (`source-control.md`, Stage parcial).

### Comentários
- Passar o mouse numa linha mostra "+" na margem; clicar abre o comentário daquela linha, arrastar
  na margem abre de um intervalo (dentro do mesmo trecho: para numa região recolhida, num comentário
  ou no fim do arquivo), c abre nas linhas marcadas ou na do cursor (review.add-comment).
- O campo aceita Markdown; ⌘Enter salva, Esc cancela. O comentário salvo aparece sob as linhas, com
  editar (review.edit-comment) e apagar (review.delete-comment).
- Cada comentário guarda o arquivo, o lado (antes ou depois), as linhas, o texto delas e 3 linhas de
  contexto. Quando o diff muda (o agente mexeu de novo), ele é reposicionado pelo texto e pelo
  contexto; sem achar, fica "desatualizado" no topo do arquivo, com o trecho antigo, até o dono
  apagar ou mover (no menu do clique nele, "Mover para as linhas marcadas": marcar as linhas novas e
  apertar c).
- Ficam guardados por worktree até enviar ou apagar, e sobrevivem a fechar o app.

### Enviar ao agente
- "Enviar ao agente" (review.send-comments) junta todos os comentários num texto só, na ordem dos
  arquivos e das linhas: para cada um, o caminho, as linhas, o trecho citado e o comentário.
- Vai ao terminal do agente daquela worktree por colagem, **sem Enter**, como o seletor de elementos
  (`docs/adr/0018-element-picker.md`): o dono lê e aperta Enter. Só num programa que aceita colagem
  segura (bracketed paste); senão, ou sem agente na worktree, vai para a área de transferência, com
  aviso.
- Enviados saem da lista e entram no histórico da worktree (review.show-sent).
  review.clear-comments apaga os não enviados, com confirmação.

### Autoria
- Com `review.authorship` ligada (padrão), cada edição de um agente aberto pelo Cadex (Edit, Write,
  MultiEdit, NotebookEdit) marca as linhas que ele escreveu (`docs/adr/0027-local-authorship.md`).
- Na aba de revisão, as linhas do agente têm uma marca discreta na margem; passar o mouse diz qual
  sessão escreveu. review.toggle-authorship liga e desliga a marca.
- Mudança no disco sem evento do agente vira "dono". O que não dá para posicionar com certeza fica
  sem marca.
- review.export-authorship salva um JSON (arquivo, intervalos, sessão) onde o dono escolher. Nada vai
  para o git.

## Estados
- **Sem mudanças contra a base:** "Nada mudou desde <base>", com trocar a base.
- **Calculando:** a árvore e os cabeçalhos aparecem primeiro; os trechos chegam conforme ficam
  prontos, sem travar a janela.
- **Pronto:** arquivos empilhados, comentários sob as linhas.
- **Comentários pendentes:** o botão "Enviar ao agente (N)" no topo da aba.
- **Autoria desligada:** sem marcas; nada é gravado.

## Casos de borda
- Diff grande (5 mil linhas em 50 arquivos) -> abre e rola sem engasgo: calculado fora da linha
  principal, só o que aparece é desenhado.
- Arquivo binário -> "Arquivo binário"; imagem -> o diff de imagem (`source-control.md`); acima de
  2 MB -> "Arquivo grande demais para o diff" com "Abrir o arquivo".
- A worktree foi removida com a aba aberta -> a aba diz que a tarefa não existe mais; comentários não
  enviados ficam no histórico.
- Base que não existe mais (branch apagado) -> volta ao merge-base com a branch padrão, com aviso.
- Comentário num arquivo que o agente apagou -> "desatualizado", com o trecho antigo.
- Sessão do agente aberta fora do Cadex -> sem autoria para as edições dela (vira "dono" quando
  mudar no disco).
- Arquivo acima de 2 MB, ou a worktree acima de 50 MB de versões guardadas -> a autoria daquele
  arquivo para, com aviso na margem.

## Critérios de aceite
- [ ] A aba de revisão de uma worktree mostra as mudanças commitadas, staged, não staged e novas
      contra o ponto de partida da tarefa, e git.review-set-base troca a base.
- [ ] j / k / n / p levam ao próximo e ao anterior arquivo e trecho; regiões sem mudança recolhem e
      expandem.
- [ ] 5 mil linhas em 50 arquivos abrem e rolam sem engasgo (`make perf`).
- [x] Um comentário numa linha e outro num intervalo, enviados juntos, chegam ao terminal do agente
      num texto só, sem Enter, com caminho, linhas e trecho citado (2026-11-15, no app de release:
      o texto dos dois conferido; a colagem segura, sem Enter, num agente falso que gravou o que
      recebeu).
- [x] Depois de o agente editar o arquivo, o comentário segue a linha certa; sem achar, fica
      "desatualizado" (testes da feature review e da aba).
- [x] Comentários sobrevivem a fechar e abrir o app (teste: lidos de novo do arquivo da worktree).
- [ ] Uma edição do agente marca as linhas dele; uma edição do dono no editor marca as do dono.
- [ ] O que o `cadex hook` manda ao app no PostToolUse não tem o arquivo inteiro nem o texto da
      conversa.
- [ ] Com `review.authorship` desligada, o kit da sessão não tem o hook PostToolUse.

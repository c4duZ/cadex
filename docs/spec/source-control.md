# source-control

## Para que serve
Ver e mandar as mudanças do repositório sem sair do Cadex: o que mudou, o diff, stage, commit, push
e pull. Os agentes mexem no código pelo terminal; aqui se confere e se faz o commit.

## Comportamento

### Painel
- O painel lateral tem duas vistas: Arquivos (o explorer) e Git. O comando "Mostrar o Git" (⇧⌘G)
  troca para a vista Git; "Mostrar os arquivos" (⇧⌘E) volta.
- No cabeçalho da barra lateral (`sidebar.md`, "Cabeçalho da página"): a branch atual (ou o sha curto,
  destacado) e quantos commits à frente (↑) e atrás (↓); clicar na branch abre a troca de branch.
  Fetch, pull e push à direita, o resto no "⋯".
- Duas listas: "Staged" e "Mudanças" (não staged, inclusive arquivos novos). Cada linha tem o ícone
  do arquivo, o nome, a pasta em cinza e a letra do tipo com a cor dele: M modificado, A adicionado,
  D apagado, R renomeado (com o nome antigo), U em conflito, ? novo não rastreado.
- Cada linha tem stage (+) ou unstage (−) ao passar o mouse; os títulos das listas têm "tudo".
- Clicar numa linha abre o diff numa aba (spec "Diff" abaixo). Menu de contexto: abrir o arquivo,
  stage/unstage, descartar, revelar no Finder (cada item roda um comando git.*).
- Campo de mensagem embaixo das listas; ⌘Enter faz o commit do que está staged. Sem nada staged, o
  commit pergunta se é para incluir todas as mudanças.
- Botões: fetch, pull (só fast-forward), push. Push sem upstream oferece publicar a branch
  (`push -u origin <branch>`).
- O painel atualiza sozinho quando o repositório muda (arquivo salvo, commit no terminal, checkout).

### Ações destrutivas
- Descartar pede confirmação, dizendo o que se perde. Arquivo novo descartado vai para a Lixeira.
- Pull que não é fast-forward é recusado com a mensagem "As branches divergiram: faça merge ou
  rebase no terminal".
- Push recusado (o remoto tem commits novos) mostra a mensagem do git; nunca força.

### Branches
- "Trocar de branch" lista as branches locais e as remotas (sem as já rastreadas), com busca, na
  paleta. Escolher uma remota cria a local rastreando. Com mudanças que impedem o checkout, mostra a
  mensagem do git e não muda nada.

### Diff
- Aba com o arquivo antes (HEAD ou o índice) e depois (índice ou o disco), lado a lado, com as
  linhas removidas em vermelho à esquerda e as adicionadas em verde à direita, e o destaque de
  sintaxe do editor. O comando "Alternar diff lado a lado/unificado" troca para uma coluna só, com o
  patch.
- Arquivo binário: "Arquivo binário, sem diff". Arquivo acima de 2 MB: "Arquivo grande demais para o
  diff" com "Abrir o arquivo".

### Diff contra base (plano 21)
- O diff de uma worktree inteira contra uma base, que a aba de revisão mostra (`review.md`): as
  mudanças commitadas desde a base, as staged, as não staged e os arquivos novos, numa lista de
  arquivos com os trechos de cada um.
- A base padrão é o merge-base entre a worktree e o branch de partida que o New Task gravou
  (`worktrees.md`); sem ele, o merge-base com a branch padrão do repositório. Qualquer commit ou
  branch serve de base.
- Também o diff entre as pontas de duas worktrees (dois branches), para comparar duas tentativas da
  mesma tarefa.
- Calculado fora da linha principal, pelo binário `git`, com o tempo limite de sempre.

### Stage parcial (plano 21)
- Stage e unstage de um trecho ou de linhas escolhidas de um trecho, na aba de revisão: só aquelas
  linhas entram (ou saem) do índice; o resto do arquivo fica como estava.
- Arquivo novo: a primeira linha posta no stage faz o git conhecer o arquivo, e só ela entra.
- Pelo `git`, dentro do workspace autorizado. O git recusou (o arquivo mudou embaixo): a mensagem
  dele, e o diff é recalculado.

### Imagem (plano 21)
- Imagem mudada (png, jpg, gif, webp, heic, pdf de uma página) mostra antes e depois em três modos
  (git.review-image-mode): lado a lado, deslizar (uma barra separa antes e depois) e sobrepor (com
  opacidade). Tamanho e dimensões dos dois lados embaixo.
- Imagem nova ou apagada: só o lado que existe. Acima de 20 MB: só os tamanhos e "Abrir o arquivo".

### Conflito em três vias (plano 21)
- Arquivo em conflito (U) abre em três colunas, a base comum, a nossa versão e a deles, e o
  resultado embaixo, editável.
- Por bloco em conflito: "Ficar com a nossa" (git.accept-ours), "Ficar com a deles"
  (git.accept-theirs), "As duas" (git.accept-both, a nossa e depois a deles) ou editar à mão no
  resultado.
- "Marcar resolvido" (git.mark-resolved) grava o resultado e faz o stage. Se ainda houver marcador de
  conflito (`<<<<<<<`, `=======`, `>>>>>>>`) no resultado, recusa com aviso dizendo a linha.

### Menu de contexto
- No menu do app (como o do explorer), só o que vale para os arquivos clicados, nada apagado (o
  dono, 2026-10-20): "Abrir o arquivo", "Abrir ao lado" e "Abrir em nova aba"; "Ver o diff", "Ver o
  diff ao lado" e "Ver o diff em nova aba"; "Stage" só em mudanças, "Unstage" só no que está em
  stage; "Descartar as mudanças"; "Revelar no Finder". Arquivo apagado não tem abrir nem revelar.
- "Ver o diff" e "Abrir o arquivo" seguem a configuração "Abrir arquivos"; as outras escolhem na hora.

### Explorer
- Arquivos alterados aparecem no explorer com a cor do tipo de mudança e a letra; as pastas ficam
  sem marca, como no desenho da aba Files.

### O git
- Tudo passa pelo binário `git` do usuário, com tempo limite (30 s; fetch, pull e push, 2 min) e
  saída limitada. Sem git instalado, o painel diz "O git não foi encontrado" com o comando para
  instalar (`xcode-select --install`; no Windows, o link do Git for Windows).
- No Windows, o git é procurado no PATH e, se não estiver lá, onde o Git for Windows instala: em
  Arquivos de Programas (instalação para todos) e em AppData\Local\Programs (só para o usuário).
- Só roda git dentro do workspace autorizado.

## Estados
- **Sem repositório:** "Esta pasta não é um repositório git" com "Inicializar repositório".
- **Git ausente:** a mensagem acima.
- **Carregando:** indicador no cabeçalho enquanto uma ação roda.
- **Limpo:** "Nenhuma mudança".
- **Erro:** a mensagem do git, curta, embaixo do botão de commit.

## Casos de borda
- Nome com espaço, acento ou aspas -> aparece e funciona como os outros.
- Renomeação -> uma linha "R antigo → novo".
- Repositório com milhares de arquivos alterados -> a lista mostra os primeiros 1000 e um aviso.
- Submódulo -> aparece como uma linha, sem entrar nele.
- Conflito de merge -> lista própria "Conflitos" no topo; o resto como sempre.

## Critérios de aceite
- [x] Status em porcelain v2 lido certo com renomeação, espaço e acento no nome.
- [x] Stage, unstage, commit e diff funcionam num repositório temporário.
- [x] Pull fast-forward recusado quando as branches divergem.
- [x] Sem git, a mensagem clara aparece.
- [x] O painel atualiza depois de um commit feito no terminal.
- [x] O explorer marca os alterados.
- [x] O diff lado a lado mostra removidas e adicionadas com destaque de sintaxe.
- [x] O diff contra base de uma worktree traz commitadas, staged, não staged e novas; o diff entre
      duas worktrees traz o que difere nas pontas (`core/features/source-control/review_test.zig`).
- [x] Stage de duas linhas de um trecho põe só elas no índice; unstage as tira; num arquivo novo,
      só a linha escolhida entra (o mesmo teste, e no app de release a mudança do cursor).
- [x] Uma imagem mudada aparece lado a lado, com a barra de deslizar e sobreposta (conferido no app
      de release, 2026-11-15).
- [x] Um conflito resolvido bloco a bloco ("nossa" num, "deles" noutro) grava o resultado e faz o
      stage; com um marcador sobrando, "Marcar resolvido" recusa (dois blocos no teste do núcleo; no
      app de release, "A deles" e "Marcar resolvido").

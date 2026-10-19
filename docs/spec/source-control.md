# source-control

## Para que serve
Ver e mandar as mudanças do repositório sem sair do Cadex: o que mudou, o diff, stage, commit, push
e pull. Os agentes mexem no código pelo terminal; aqui se confere e se faz o commit.

## Comportamento

### Painel
- O painel lateral tem duas vistas: Arquivos (o explorer) e Git. O comando "Mostrar o Git" (⇧⌘G)
  troca para a vista Git; "Mostrar os arquivos" (⇧⌘E) volta.
- No topo: a branch atual (ou "HEAD destacado em <sha curto>"), o upstream e quantos commits à frente
  (↑) e atrás (↓). Clicar na branch abre a troca de branch.
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

### Explorer
- Arquivos alterados aparecem no explorer com a cor do tipo de mudança, e pastas que contêm
  alterados com um ponto.

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
- **Carregando:** indicador no topo enquanto o status roda.
- **Limpo:** "Nenhuma mudança".
- **Erro:** a mensagem do git, curta, embaixo dos botões.

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

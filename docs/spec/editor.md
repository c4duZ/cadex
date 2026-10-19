# editor

## Para que serve
Ler código numa aba do Cadex, com a cara de um editor (números de linha, destaque de sintaxe,
dobras), e fazer edições pequenas. O código de verdade é escrito pelos agentes no terminal; aqui se
lê, confere e corrige uma linha (ADR 0006).

## Comportamento

### Abrir
- Abrir um arquivo de texto (explorer, ⌘P, ⌘⇧F, ⌘+clique num caminho do terminal) abre uma aba de
  editor com o nome do arquivo no título. Abrir de novo um arquivo já aberto vai para a aba dele.
- Abrir de um resultado do ⌘⇧F leva o cursor à linha do resultado, centralizada.
- A linguagem vem da extensão (e de nomes como `Makefile`, `Dockerfile`). Linguagens com destaque no
  MVP: TypeScript, JavaScript, Python, Rust, Go, Swift, Zig, C, C++, Java, HTML, CSS, JSON, YAML,
  TOML, Shell e Markdown. Outras abrem como texto puro.
- Arquivo binário não abre no editor: a aba mostra "Arquivo binário" com "Abrir no app padrão".
  Imagem, vídeo, áudio e PDF abrem no visualizador de mídia.

### Ver
- Fonte monoespaçada (a do terminal), números de linha numa régua à esquerda, a linha do cursor
  destacada de leve.
- Destaque de sintaxe com as cores do tema: palavra-chave, texto, número, comentário, função, tipo,
  constante, propriedade, operador, pontuação.
- Setinha de dobrar ao lado de cada bloco que ocupa mais de uma linha (funções, classes, blocos,
  objetos). Clicar dobra; o bloco dobrado vira uma linha com "…". Clicar de novo desdobra.
- Linhas longas quebram na largura da aba (sem rolagem horizontal).

### Editar
- Digitar, apagar, desfazer (⌘Z), refazer (⇧⌘Z), buscar (⌘F) e selecionar funcionam como em
  qualquer campo de texto do Mac. Tab insere a indentação do arquivo (tab ou espaços, detectado).
- Aba com mudança não salva mostra um ponto no título. ⌘S salva. Fechar com mudança pergunta se
  salva.
- O destaque acompanha a digitação sem recolorir o arquivo inteiro.

### Disco
- O arquivo mudou no disco (um agente editou): sem edição pendente na aba, recarrega sozinho mantendo
  a posição; com edição pendente, avisa no topo da aba com "Recarregar" e "Manter o meu".
- O arquivo foi apagado: a aba avisa e "Salvar" o recria.

### Limites
- Até 10 MB abre normalmente. Acima de 1 MB, sem destaque de sintaxe nem dobras (avisa no topo).
- Acima de 10 MB: abre só para leitura, os primeiros 10 MB, avisando.

## Estados
- **Carregando:** arquivo grande sendo lido: a aba aparece na hora, o texto em seguida.
- **Pronto:** o texto.
- **Erro:** sem permissão ou fora do workspace: mensagem na aba.

## Casos de borda
- Arquivo vazio -> abre com uma linha.
- Arquivo em UTF-8 inválido -> abre com os bytes ruins trocados pelo caractere de substituição e só
  para leitura (salvar estragaria o arquivo).
- Final de linha CRLF -> mantido ao salvar.
- Arquivo de 100 MB -> abre os primeiros 10 MB só para leitura, sem travar.

## Critérios de aceite
- [x] Destaque de um arquivo de exemplo de cada linguagem dá os tipos esperados nas posições certas.
- [x] Uma edição reanalisa só o trecho alterado.
- [x] Dobras aparecem em funções e blocos de várias linhas.
- [ ] `core/features/terminal/render.zig` abre com destaque e dobras.
- [ ] Editar e salvar grava no disco e tira o ponto do título.
- [ ] Mudança no disco sem edição pendente recarrega a aba.
- [ ] Arquivo de 100 MB abre sem travar.
- [ ] Binário mostra o aviso em vez do conteúdo.

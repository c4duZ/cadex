# explorer

## Para que serve
Ver e mexer nos arquivos do workspace sem sair do app: uma árvore no painel lateral, com as
operações do Finder que importam para quem programa.

## Comportamento

### Árvore
- O painel lateral mostra a árvore do workspace, com a pasta raiz no título.
- Pastas carregam sob demanda: só o conteúdo de uma pasta aberta é lido. Abrir a raiz não lê a
  árvore inteira.
- Ordem: pastas primeiro, depois arquivos; dentro de cada grupo, ordem alfabética natural sem
  diferenciar caixa (`file2` antes de `file10`).
- Cada linha tem um ícone Phosphor pelo tipo: pasta (aberta/fechada), código, Markdown, imagem,
  vídeo, áudio, PDF, arquivo compactado, configuração (JSON, YAML, TOML) e genérico.
- Arquivos ocultos (nome começando com `.`) e ignorados pelo `.gitignore` aparecem apagados. O
  comando "Mostrar arquivos ocultos" alterna se aparecem; a escolha fica nas configurações. `.git`
  nunca aparece.
- A árvore atualiza sozinha quando algo muda no disco (outro programa, o terminal, o git). As pastas
  abertas continuam abertas e a seleção é mantida.

### Aparência (no estilo do explorador do VS Code)
O dono comparou com o Terax e preferiu o explorador do VS Code (2026-10-19). O comportamento abaixo
segue a documentação pública do VS Code; o código de cores por tipo vem do CodeEdit (MIT).
- Linhas de largura inteira, 22 pt de altura, recuo de 8 pt por nível depois da seta.
- Um clique abre: arquivo na aba, pasta abre ou fecha. Com ⌘ ou ⇧ o clique só monta a seleção.
  Dois cliques para tudo foi a queixa do dono (2026-10-19).
- Guias de recuo: linhas verticais finas que descem do centro da seta de cada pasta aberta e
  passam pelos filhos dela, com o ponteiro sobre a árvore.
- Ao passar o ponteiro, a linha ganha um fundo leve. A selecionada tem o fundo na cor do tema e,
  com a árvore em foco, uma borda fina da mesma cor; sem foco, só o fundo, mais fraco.
- Pastas compactas: uma pasta que só tem outra pasta dentro aparece numa linha só, "src/main/java",
  até a primeira pasta com mais de um item ou com arquivo. Abrir a linha abre a última pasta da
  cadeia; as ações (novo arquivo, renomear, apagar) valem para ela.
- Ícones pelo tipo, os do Material Icon Theme do VS Code quando ele conhece o nome (Docker, Git,
  Python, Rust, Makefile, licença, `.env`; pastas `src`, `tests`, `docs`, `.github`,
  `node_modules`...), nas cores dele; o resto em Phosphor: pastas na cor do tema, arquivos na cor
  do tipo ou cinza (ADR 0011). As abas usam os mesmos ícones.
- Git: o nome do arquivo alterado fica na cor da mudança, com a letra (M, A, U, D) alinhada à
  direita; a pasta que contém alterados ganha o nome levemente colorido e um ponto.
- Cabeçalho: o nome da pasta raiz em maiúsculas, pequeno; à direita, buscar arquivo, novo arquivo,
  nova pasta, recarregar e recolher tudo.
- As pastas abertas são lembradas por raiz: reabrir o app ou voltar àquela pasta abre as mesmas.
- Renomeando, um nome inválido (vazio, com `/`, ou de um irmão que já existe) deixa o campo
  vermelho antes de confirmar.

### Teclado
- ↑ e ↓ movem a seleção; → abre a pasta (ou desce para o primeiro filho); ← fecha a pasta (ou sobe
  para a pasta pai).
- Enter abre o arquivo (visualizador do plano 5; até lá, no app padrão do sistema) ou abre e fecha
  a pasta.
- F2 renomeia; ⌘⌫ apaga para a Lixeira; ⌘C e ⌘V copiam e colam arquivos. Essas teclas valem só
  com o foco na árvore (o terminal usa as mesmas). ⇧⌘E leva o foco para a árvore.

### Operações (todas são comandos, também no menu de contexto)
- **Novo arquivo** e **Nova pasta**: criam dentro da pasta selecionada (ou na pasta do arquivo
  selecionado) e já entram no modo de renomear com o nome sugerido selecionado.
- **Renomear**: edição no próprio lugar da linha. Enter confirma, Esc cancela. Nome vazio, com `/`
  ou igual a um irmão existente é recusado com a mensagem ao lado.
- **Mover**: arrastar arquivos e pastas para outra pasta da árvore. Arquivos arrastados de fora
  do app (Finder) ainda não entram; ficam para depois do MVP.
- **Copiar** e **Colar**: copiam arquivos e pastas; colando ao lado de um homônimo, o novo ganha
  " cópia" no nome.
- **Apagar**: vai para a Lixeira do sistema, nunca apaga de vez. Mais de um item pede confirmação.
- **Abrir arquivo** segue a configuração "Abrir arquivos" (ao lado ou em nova aba). **Abrir ao
  lado** e **Abrir em nova aba**, logo depois dele no menu de contexto, escolhem na hora.
- **Revelar no Finder**, **Copiar caminho** e **Copiar caminho relativo**.
- **Abrir no terminal**: o painel com foco faz `cd` para a pasta (do arquivo, se for arquivo).
- **Arrastar para o terminal**: soltar arquivos num painel cola os caminhos escapados para o shell,
  como arrastar do Finder.

### Leitura de arquivo (para os visualizadores)
- O núcleo entrega o conteúdo de um arquivo só se ele estiver num diretório autorizado, tiver até
  10 MB e não for binário (há um byte nulo nos primeiros 8 KB). Fora disso, diz por quê.

## Estados
- **Carregando:** pasta aberta pela primeira vez e lenta (disco de rede): um indicador na linha.
- **Vazio:** pasta sem conteúdo visível: a linha "Pasta vazia", apagada.
- **Erro:** sem permissão de leitura: a pasta mostra "Sem permissão" e não abre.
- **Pronto:** a árvore.

## Casos de borda
- Pasta com 10 000 arquivos -> abre sem travar a interface.
- Renomear para o nome que já existe -> recusado, nada muda no disco.
- Mover uma pasta para dentro dela mesma -> recusado.
- Arquivo apagado por fora enquanto selecionado -> some da árvore, a seleção vai para o vizinho.
- Link simbólico para fora do workspace -> aparece na árvore com o ícone de link, mas não abre.
- Arquivo binário ou acima de 10 MB pedido pelo visualizador -> recusado com o motivo.

## Critérios de aceite
- [x] Listar uma pasta devolve nome, tipo, tamanho e se é ignorada, pastas primeiro.
- [x] Criar, renomear, mover e copiar funcionam e recusam fora do workspace.
- [x] Renomear para um nome existente é recusado.
- [x] Mover uma pasta para dentro dela mesma é recusado.
- [x] A observação avisa criação e remoção de arquivo numa pasta observada.
- [x] Ler arquivo recusa binário e arquivo acima do limite.
- [x] Apagar manda para a Lixeira.
- [x] Expandir `core/features/` mostra as pastas das features com ícone de pasta.
- [ ] Arrastar um arquivo para o terminal cola o caminho escapado.
- [x] Todas as operações estão registradas como comandos e aparecem na paleta.
- Pasta compacta e o disco muda (entra um segundo item na pasta do meio) -> a cadeia se desfaz na
  próxima leitura.

## Critérios de aceite (aparência)
- [x] Uma cadeia de pastas com uma pasta só dentro aparece numa linha, e abrir mostra o conteúdo da
  última.
- [x] As pastas abertas voltam ao reabrir o app.
- [ ] Guias de recuo, seleção e cores por tipo conferidos num print lado a lado com o VS Code.

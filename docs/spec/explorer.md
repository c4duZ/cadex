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
- Arquivos alterados no git ganham marcação quando a feature source-control existir (plano 6).
- A árvore atualiza sozinha quando algo muda no disco (outro programa, o terminal, o git). As pastas
  abertas continuam abertas e a seleção é mantida.

### Teclado
- ↑ e ↓ movem a seleção; → abre a pasta (ou desce para o primeiro filho); ← fecha a pasta (ou sobe
  para a pasta pai).
- Enter abre o arquivo (visualizador do plano 5; até lá, no app padrão do sistema) ou abre e fecha
  a pasta.
- F2 ou Enter com ⌥ renomeia; ⌘⌫ apaga para a Lixeira.

### Operações (todas são comandos, também no menu de contexto)
- **Novo arquivo** e **Nova pasta**: criam dentro da pasta selecionada (ou na pasta do arquivo
  selecionado) e já entram no modo de renomear com o nome sugerido selecionado.
- **Renomear**: edição no próprio lugar da linha. Enter confirma, Esc cancela. Nome vazio, com `/`
  ou igual a um irmão existente é recusado com a mensagem ao lado.
- **Mover**: arrastar arquivos e pastas para outra pasta da árvore.
- **Copiar** e **Colar**: copiam arquivos e pastas; colando ao lado de um homônimo, o novo ganha
  " cópia" no nome.
- **Apagar**: vai para a Lixeira do sistema, nunca apaga de vez. Mais de um item pede confirmação.
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
- [ ] Listar uma pasta devolve nome, tipo, tamanho e se é ignorada, pastas primeiro.
- [x] Criar, renomear, mover e copiar funcionam e recusam fora do workspace.
- [x] Renomear para um nome existente é recusado.
- [x] Mover uma pasta para dentro dela mesma é recusado.
- [x] A observação avisa criação e remoção de arquivo numa pasta observada.
- [x] Ler arquivo recusa binário e arquivo acima do limite.
- [ ] Apagar manda para a Lixeira.
- [ ] Expandir `core/features/` mostra as pastas das features com ícone de pasta.
- [ ] Arrastar um arquivo para o terminal cola o caminho escapado.
- [ ] Todas as operações estão registradas como comandos e aparecem na paleta.

# terminal

## Para que serve
Rodar o shell do usuário dentro do Cadex, em abas e painéis, com a resposta de um terminal nativo
rápido. É onde os agentes de código rodam. Comportamento inicial igual ao terminal do Terax no uso
do dia a dia, mais simples por dentro e com o texto nítido.

## Comportamento

### Sessões
- Cada painel roda uma sessão com o shell de login do usuário (`$SHELL`). O shell pode ser trocado nas
  configurações.
- O terminal se apresenta como compatível com xterm-256color e suporta true color.
- O terminal acompanha a pasta atual da sessão pelo aviso do shell (OSC 7). É ela que aparece na aba
  e na barra de status.
- Quando o shell termina (`exit`, Ctrl+D), o painel fecha. Se era o último painel da aba, a aba fecha.

### Abas
- ⌘T abre uma aba de terminal na pasta da sessão ativa; sem sessão ativa, na pasta do workspace; sem
  workspace, na pasta pessoal.
- O título da aba é o nome da pasta atual. O usuário pode renomear, e o nome dado fica mesmo depois
  de mudar de pasta.
- ⌘W fecha o painel ativo; se for o único da aba, fecha a aba.
- ⌘1 a ⌘9 vão para a aba daquela posição; Ctrl+Tab e Ctrl+Shift+Tab alternam pela ordem de uso.

### Divisões
- ⌘D divide o painel ativo para a direita; ⌘Shift+D, para baixo. O painel novo abre na mesma pasta.
- O tamanho das divisões muda arrastando a linha entre os painéis.
- ⌘] e ⌘[ passam o foco para o próximo e o anterior.
- O painel com foco tem destaque discreto; os outros continuam atualizando normalmente.

### Texto e aparência
- Fonte padrão: SF Mono, 13 pt. Fonte, tamanho e espaçamento entre letras são configuráveis.
- O texto é desenhado na resolução real da tela (Retina incluída), alinhado aos pixels, sem escalar
  uma imagem pronta. Nada de texto borrado em nenhum tamanho de fonte ou zoom.
- Cores vêm do tema ativo (ver a spec de themes). Temas do Terax podem ser importados.
- Cursor em barra, sem piscar, por padrão. Estilo (barra, bloco, sublinhado) e piscar configuráveis.
- ⌘+ e ⌘- mudam o tamanho da fonte; ⌘0 volta ao padrão.

### Rolagem
- Histórico (scrollback) padrão de 10 mil linhas, configurável.
- Rolar com o trackpad é suave; ao digitar, a tela volta para o fim.
- Programas de tela cheia (vim, htop, less) recebem a rolagem como o programa espera.

### Seleção e copiar
- Arrastar seleciona; duplo clique seleciona a palavra; triplo clique, a linha.
- ⌘C copia a seleção. Sem seleção, ⌘C não faz nada (Ctrl+C continua sendo o interromper do shell).
- ⌘A seleciona todo o conteúdo do painel, inclusive o histórico.
- A configuração "copiar ao selecionar" decide se selecionar copia. Desligada (padrão), a área de
  transferência só muda com ⌘C ou o comando de copiar: passar o mouse, clicar ou selecionar não
  copia nada, e o que já estava copiado (texto, imagem, arquivo) continua lá para colar. Ligada,
  terminar uma seleção copia o texto dela; passar o mouse sem selecionar nunca copia.

### Links
- URLs e caminhos de arquivo aparecem sublinhados ao passar o mouse com ⌘ pressionado.
- ⌘+clique abre a URL no navegador; um caminho de arquivo abre no Cadex (editor, Markdown ou mídia,
  conforme o tipo).

### Busca
- ⌘F abre a busca do painel ativo: destaca todas as ocorrências, inclusive no histórico; Enter e
  Shift+Enter navegam; Esc fecha.

### Colar (⌘V)
Ao colar, o terminal olha o que está na área de transferência, nesta ordem, e usa o primeiro que
existir:

1. **Arquivos copiados** (por exemplo, no Finder): cola os caminhos completos, cada um escapado para
   o shell (espaços e caracteres especiais protegidos), separados por espaço.
2. **Imagem** (print de tela, imagem copiada do navegador): salva a imagem como PNG num arquivo
   temporário e cola o caminho desse arquivo, escapado para o shell.
3. **Texto**: cola o texto. Se o programa em execução ativou o modo bracketed paste, o texto vai
   marcado como colagem, para não ser executado linha a linha como digitação.

Colar é responsabilidade da interface de cada plataforma: no macOS, a área de transferência do
sistema (NSPasteboard); no Windows, a do Win32. O núcleo recebe só o texto final a enviar.

### Arrastar arquivos
- Arquivos arrastados do Finder ou do explorer para um painel viram caminhos escapados, separados
  por espaço, como na colagem de arquivos.

### Teclado
- Edição estilo Mac no prompt: ⌥← e ⌥→ andam por palavra; ⌘← e ⌘→ vão ao início e ao fim da
  linha; ⌥⌫ apaga a palavra anterior; ⌘⌫ apaga até o início da linha; ⌥⌦ e ⌘⌦ apagam a palavra
  seguinte e até o fim da linha. Enviados como os atalhos de shell equivalentes (Esc b, Ctrl+A...).
- ⌘K abre a paleta de comandos, mesmo com o foco no terminal. Nada é enviado ao shell.
- ⌘L limpa a tela (o histórico continua disponível).
- Option digita os caracteres especiais do macOS por padrão; uma configuração faz o Option esquerdo
  funcionar como Meta (para atalhos de shell como Option+B).
- Setas, F1–F12, Home/End/PgUp/PgDn e combinações com Ctrl, Shift e Meta chegam ao programa no
  formato que ele pediu: modo de aplicação das setas (vim, less, htop) e protocolo de teclado do
  kitty (neovim, fish).
- Atalhos do app nunca roubam teclas de controle que os programas usam (Ctrl+B, Ctrl+R, Ctrl+A...).

### Fechar e restaurar
- Fechar painel, aba ou janela com um processo rodando em primeiro plano (por exemplo, um agente ou
  um servidor) pede confirmação. A confirmação pode ser desligada nas configurações.
- Ao reabrir o app, os spaces voltam com as abas, as divisões e a pasta de cada painel. O conteúdo
  antigo da tela não volta: cada painel começa um shell novo.

## Estados
- **Abrindo:** o painel aparece na hora; o prompt surge assim que o shell responde.
- **Erro ao abrir o shell** (shell configurado não existe, pasta sem permissão): o painel mostra a
  mensagem de erro e um botão para tentar com o shell padrão.
- **Sessão encerrada por erro:** o painel mostra o código de saída em vez de fechar sozinho, para não
  esconder o motivo.

## Casos de borda
- Área de transferência vazia: ⌘V não envia nada.
- Vários arquivos copiados: todos os caminhos, na ordem copiada.
- Imagem e texto juntos na área de transferência (comum ao copiar do navegador): vale a imagem.
- Falha ao salvar a imagem temporária: avisa o erro e não cola nada.
- Saída enorme de uma vez (`cat` de um arquivo de centenas de MB): a janela continua respondendo e
  Ctrl+C interrompe.
- Janela redimensionada: as linhas se reorganizam sem perder o histórico.
- Emoji, acentos e caracteres asiáticos ocupam a largura certa e não desalinham a tela.

## Fora do escopo
- Modo em blocos e terminal privado (cortados do Cadex; ver "O que eu não quero" no CLAUDE.md da raiz).
- Imagens dentro do terminal (protocolos kitty e sixel), ligaduras de fonte, modo de controle do
  tmux e terminal suspenso por atalho global. Podem entrar depois, cada um com a própria decisão.

## Critérios de aceite
- [x] Copiar um arquivo com espaço no nome no Finder e colar resulta num caminho que o shell aceita.
- [x] Colar um print de tela cola o caminho de um PNG que existe e abre a imagem.
- [x] Colar texto num programa com bracketed paste ativo não executa as linhas automaticamente.
- [x] Com "copiar ao selecionar" desligado e qualquer coisa copiada, passar o mouse e selecionar
      texto no terminal não muda a área de transferência; ⌘V ainda cola o que estava lá.
- [x] Com "copiar ao selecionar" ligado, terminar uma seleção copia o texto dela.
- [ ] ⌘K com o foco no terminal abre a paleta e não envia nada ao shell.
- [ ] No zsh e no bash, ⌥← ⌥→ ⌘← ⌘→ ⌥⌫ ⌘⌫ movem e apagam como descrito em Teclado.
- [ ] Em tela Retina, o texto em SF Mono 13 pt sai nítido (comparado lado a lado com o Terminal do
      macOS no mesmo tamanho).
- [ ] `cat` de um arquivo de 100 MB não trava a janela, e Ctrl+C interrompe em menos de 1 segundo.
- [ ] ⌘D, ⌘Shift+D, ⌘W e ⌘T funcionam e a aba nova abre na pasta da sessão ativa.
- [ ] Fechar uma aba com `sleep 100` rodando pede confirmação; com o shell parado, fecha direto.
- [ ] Reabrir o app restaura abas, divisões e pastas.
- [ ] `vim`, `htop` e `less` funcionam, inclusive com rolagem e redimensionamento.

# terminal

## Para que serve
Rodar o shell do usuário dentro do Cadex, em abas e painéis, com a resposta de um terminal nativo
rápido. É onde os agentes de código rodam. Comportamento inicial igual ao de um terminal moderno no uso
do dia a dia, mais simples por dentro e com o texto nítido.

## Comportamento

### Sessões
- Cada painel roda uma sessão com o shell de login do usuário (`$SHELL`). O shell pode ser trocado nas
  configurações.
- O terminal se apresenta como compatível com xterm-256color e suporta true color.
- O terminal acompanha a pasta atual da sessão pelo aviso do shell (OSC 7). É ela que aparece na aba
  e na barra de status.
- No Windows, o shell padrão é o PowerShell 7 (pwsh) quando instalado, senão o Windows PowerShell,
  senão o cmd. O PowerShell recebe a integração de shell sozinho, sem o usuário editar nada: o
  `$PROFILE` dele roda primeiro, e depois o prompt dele passa a avisar a pasta atual (OSC 7). Temas
  de prompt (oh-my-posh, Starship) continuam iguais, porque o aviso só é acrescentado ao prompt. O
  cmd fica sem integração, e a pasta da aba é a de abertura.
- No Windows, a pasta avisada (file:///C:/Users/x) vira `C:\Users\x`, com barras invertidas.
- **Integração do zsh** (plano 22, fase C): no Mac, o zsh das abas abre com uma pasta de
  inicialização do Cadex (`ZDOTDIR`), a técnica do Ghostty e do iTerm, porque prefixar o `PATH` não
  funciona (o shell de login, com o path_helper, e o `.zshrc` do dono o reordenam). Essa pasta
  devolve o `ZDOTDIR` do dono (ou nenhum, e o zsh lê o `$HOME`), lê o `.zshenv` dele e define uma
  função `claude`; daí o zsh lê o `.zprofile`, o `.zshrc` e o `.zlogin` do dono como sempre. Não
  escreve nada na tela, não falha a abertura, vale também para `zsh -c`, e um zsh aberto dentro da
  aba já é o do dono, sem a função.
  - A função roda `cadex claude`, que dá o kit da sessão ao `claude` interativo digitado na aba
    (`docs/spec/memory.md`, "O `claude` digitado à mão"); sem o `cadex`, roda o `claude` de verdade.
  - A conta (plano 33 F): a da aba, quando ela tem `CLAUDE_CONFIG_DIR` (escrito na linha ou
    exportado pelos arquivos do dono); sem, a mesma de uma sessão que o Cadex abre ali (a do projeto,
    senão a ativa, senão a padrão). A ativa é a escolhida na barra de cima com um shell no foco, e
    cada `claude` digitado no terminal com foco a troca pela dele: o próximo terminal (⌘T, ⌘D) segue
    o último Claude (o dono, 2026-11-18).
  - Uma aba nunca herda do app o que uma sessão do Claude Code deixa aos filhos (CLAUDECODE,
    CLAUDE_CODE_* e o CLAUDE_CONFIG_DIR dela): o Cadex aberto de dentro de uma sessão passava a
    marca de sessão filha (o `claude` da aba não gravava a conversa) e a conta daquela sessão
    (`core/features/terminal/shell_env.zig`).
    Com "Sem pedir permissões" (agents.launchSkipPermissions), todo `claude` digitado ganha
    `--dangerously-skip-permissions`, menos quando a linha já diz o modo (`--permission-mode`, a
    própria flag). Vale também na gaveta de terminais.
  - Um `alias claude=` ou uma função `claude` do dono passa por cima da do Cadex: aquela aba fica
    sem o kit. Bash e fish não recebem nada.
  - Funciona nos terminais mantidos (terminal.keepSessions): o daemon herda do app o ambiente que
    liga a integração. Um daemon que já rodava antes de um app sem ela só a passa depois de sair.
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
- Cores vêm do tema ativo (ver a spec de themes).
- Cursor em barra, sem piscar, por padrão. Estilo (barra, bloco, sublinhado) e piscar configuráveis.
- ⌘+ e ⌘- mudam o tamanho da fonte; ⌘0 volta ao padrão.

### Rolagem
- Histórico (scrollback) padrão de 10 mil linhas, configurável.
- Rolar com o trackpad é suave; ao digitar, a tela volta para o fim.
- Programas de tela cheia (vim, htop, less) recebem a rolagem como o programa espera.

### Seleção e copiar
- Arrastar seleciona; duplo clique seleciona a palavra.
- O que você está escrevendo funciona como numa caixa de texto (o dono, 2026-11-18): no prompt do
  shell (o que vem depois do prompt, pela marca OSC 133 B da integração do zsh) e na caixa de
  entrada do Claude Code. ⌘A seleciona só esse texto; um segundo ⌘A seleciona tudo. Duplo clique
  no vazio ou triplo clique sobre ele também o seleciona; fora dele, selecionam o parágrafo sob o
  ponteiro (as linhas com texto até uma linha vazia). Com ele selecionado, ⌘C copia, Delete o
  apaga e uma letra o troca pelo que foi digitado. O Cadex apaga com as teclas do próprio programa:
  no shell, Ctrl+E e Ctrl+U; no Claude, um clique logo depois do texto (o cursor vai ao fim),
  Ctrl+E e um Backspace por caractere.
- ⌘C copia a seleção. Sem seleção, ⌘C não faz nada (Ctrl+C continua sendo o interromper do shell).
- No Windows, além do Ctrl+Shift+C (o ⌘C), Ctrl+C com texto selecionado copia, como no Windows
  Terminal; sem seleção, Ctrl+C é o interromper do shell.
- O segundo ⌘A (ou o primeiro, sem nada escrito) seleciona todo o conteúdo do painel, inclusive o
  histórico.
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
   temporário e cola o caminho desse arquivo, escapado para o shell. Com o lado maior passando de
   1568 px, a imagem é reduzida a 1568 px antes: a API do Claude reduz a esse tamanho de qualquer
   jeito, e o Claude Code levou quase 8 s para anexar um print de 2940 × 1912 (2026-10-21).
3. **Texto**: cola o texto. Se o programa em execução ativou o modo bracketed paste, o texto vai
   marcado como colagem, para não ser executado linha a linha como digitação.

Colar é responsabilidade da interface de cada plataforma: no macOS, a área de transferência do
sistema (NSPasteboard); no Windows, a do Win32. O núcleo recebe só o texto final a enviar.

### Ver a imagem colada
Agentes como o Claude Code trocam o caminho da imagem colada por uma etiqueta (`[Image #3]`), e a
imagem some da vista. O terminal liga a etiqueta ao arquivo que ele mesmo salvou na colagem:

- Depois de colar uma imagem, a primeira etiqueta `[Image #N]` nova que aparece na tela da aba, em
  até 30 s, fica ligada àquele arquivo (eram 5 s; o Claude Code passou a levar quase 8 s para
  mostrar a etiqueta de um print, 2026-10-21). Várias imagens coladas em seguida se ligam na ordem.
- Passar o mouse sobre uma etiqueta ligada mostra a miniatura da imagem ao lado do ponteiro (no
  máximo 320 × 240 pt) e o cursor de mão; tirar o mouse esconde.
- Clicar na etiqueta abre a imagem no visualizador de mídia, onde os arquivos abrem
  (configuração "Abrir arquivos": ao lado ou em nova aba).
- Comandos: "Abrir a última imagem colada ao lado" e "Abrir a última imagem colada em nova aba";
  só aparecem com um terminal com foco que já colou uma imagem.
- Vale só para o que foi colado com ⌘V no Cadex, enquanto a aba existe. Imagem colada por outro
  caminho (Ctrl+V direto no programa) não tem arquivo conhecido, e a etiqueta fica como texto.
- O mesmo número de novo (o agente reiniciou e voltou ao `#1`) passa a apontar para a colagem nova.
- Uma célula que o programa nunca escreveu conta como espaço: o Claude Code redesenha
  `[Image #1][Image #2]` pulando o espaço, e a segunda etiqueta não era achada (2026-10-21).

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
- Ao reabrir o app, os projetos voltam com as abas, as divisões e a pasta de cada painel. Com
  terminal.keepSessions desligado (o padrão), o conteúdo antigo da tela não volta: cada painel
  começa um shell novo.
- Com terminal.keepSessions ligado (plano 19, `docs/adr/0022-terminal-daemon.md`), um processo à
  parte, o daemon do terminal, é dono dos shells: fechar, travar ou atualizar o app não mata o que
  roda; ao reabrir, cada painel religa ao seu shell e a tela e o scrollback voltam. Depois de
  reiniciar o Mac, volta o scrollback salvo de cada painel, num shell novo (processo não volta). Sem
  nenhum terminal aberto, o daemon sai sozinho. Desligado, nenhum daemon roda.
- O daemon (fase E1, 2026-11-15): o programa `cadex-terminald`, no socket
  `terminal-<versão do protocolo>.sock` da pasta de sockets. Guarda de cada sessão os últimos 2 MiB
  da saída crua e os modos que o programa ligou (tela alternativa, colagem entre colchetes, mouse,
  teclado kitty); ao religar, o app recebe essa saída e, depois dela, os modos que ela sozinha não
  deixaria ligados. O app escreve, redimensiona e pergunta o programa em primeiro plano direto no
  PTY, que o daemon passa a ele. Sessão que terminou sem app ligado guarda a saída e o código de
  saída até o app religar. Enquanto nenhum app está ligado, as perguntas do programa ao terminal
  (cor de fundo, `ESC]7501;?`) ficam sem resposta.
- O app pelo daemon (fase E2, 2026-11-15): com a opção ligada (Configurações › Terminal), cada
  terminal da janela principal abre no daemon com um nome (`<instância>-<uuid>`, a instância vinda do
  caminho do arquivo de estado, para outra cópia do Cadex nunca encerrar as sessões desta) e o nome
  vai nos projetos; reabrir religa por ele, com a saída guardada e dois redimensionamentos para um programa de
  tela cheia se redesenhar. Sessão que o daemon não tem mais (o Mac reiniciou) vira um shell novo que
  mostra antes a saída gravada no SIGTERM (`scrollback/<nome>.raw`, apagado depois de lido). Depois
  de restaurar, as sessões desta instância que nenhum painel pegou de volta são encerradas. O app
  inicia o daemon (`cadex-terminald` em Contents/Helpers) na primeira vez que precisa; sem sessão e
  sem app por 3 s, ele sai. Daemon que não sobe deixa o terminal num PTY do app, como com a opção
  desligada.

### Notificações dos programas
- Um programa pode pedir uma notificação ao terminal (OSC 777 `notify;título;texto` ou OSC 9
  `texto`): ela aparece como uma notificação do macOS, com o nome do terminal; o clique traz aquele
  terminal para a frente. Não aparece enquanto você olha aquele terminal; uma nova do mesmo terminal
  substitui a anterior. Desliga em terminal.programNotifications (Configurações › Terminal, ligada
  por padrão). O kit da sessão não liga o `preferredNotifChannel` do Claude Code: as paradas do agente
  já notificam pelos hooks e pelo OSC 7501 (o dono, 2026-11-15).

### Agentes no terminal (plano 19)
- O terminal responde à pergunta `ESC]7501;?` do Claude Code com `ESC]7501;?;1` e passa a receber o
  estado da sessão (`state`, `kind`, `msg` em base64), que entrega ao app por terminal; chave
  desconhecida é ignorada.
- O desenho respeita a saída sincronizada (modo DEC 2026): desenha só no fim de cada bloco. Com
  isso o kit da sessão liga `CLAUDE_CODE_FORCE_SYNC_OUTPUT=1`. `TERM_PROGRAM` continua `Cadex`.

- Leitura (plano 15, fase C):
  - **Contraste mínimo** (terminal.minimumContrast, de 1 a 21; 1 desliga): texto que um programa
    pinta perto demais do fundo da célula vai para o branco ou o preto até a razão WCAG pedida.
    A conta é feita no shader, uma vez por letra.
  - **Altura de linha** (terminal.lineHeight, 0,8 a 2 vezes a da fonte; padrão 1,6, a da moldura nova, e um arquivo antigo no 1 passa a 1,6 uma vez) e **espaçamento entre
    letras** (terminal.letterSpacing, -1 a 4 pt, com a letra centrada na célula).
  - **Recursos OpenType** (terminal.fontFeatures: "ss01", "zero", "-liga"…). Com "calt" ou "liga"
    ligados, uma sequência de 2 a 8 símbolos na mesma linha e na mesma cor (`->`, `!=`, `===`) é
    desenhada como um sinal só sobre as células dela, quando a fonte junta essas letras (Fira Code,
    JetBrains Mono). O SF Mono não tem ligaduras. terminal.toggle-ligatures liga e desliga.

### As cores do Claude Code (plano 28, fase A)
Medido em 2026-11-17 com um `claude` de verdade (conta de teste, haiku) num terminal falso que
guardou cada byte desenhado: a abertura, o pedido, as ferramentas, o diff e a pergunta de
permissão.
- No tema padrão do Claude ("dark"), quase tudo vem em cor fixa (RGB de 24 bits, `38;2;…` e
  `48;2;…`): o fundo do diff (`61,1,0` e `2,40,0`), o texto do diff (`248,248,242`), o "Perusing…"
  laranja animado cor a cor, o texto do dono (branco), os destaques (`177,185,249`), o modo
  (`175,135,255`). O tema do Cadex não alcança nada disso: é o Claude com as cores dele.
- No tema "dark-ansi" do Claude, pedido por `--settings '{"theme":"dark-ansi"}'` (vale na sessão,
  sem mexer na configuração da conta), tudo vem nas 16 cores ANSI: o texto do dono em 97, o
  "trabalhando" em 93, os destaques e o ❯ em 94, as bordas em 37, o logo em 91 e 40, o modo em 95.
  Aí o ANSI do tema do Cadex manda nas cores do Claude.
- A status line do kit já usa ANSI (36, 32, 33, 35).
- Decisão do plano 28 (revista no 33, abaixo): o kit das sessões abertas pelo Cadex pedia o tema
  "dark-ansi" num tema escuro do Cadex e "light-ansi" num claro (fase C); o ANSI do Cadex Night é afinado para que o Claude, assim, fique
  com a cara do mockup 10. Quem digita `claude` numa aba sem o kit continua com o tema da conta.
- O que o Claude desenha continua dele: a caixa da mensagem, as ferramentas e o diff só mudam de
  cor, nunca de forma. (Revisto no plano 33: o terminal passa a trocar as cores fixas e a desenhar
  algumas formas por cima; abaixo.)

### As cores e as formas do Claude Code (plano 33, fase A)
Medido em 2026-11-18 com o Claude Code 2.1.327 (conta bkdg, Haiku), num PTY de 110 × 40 com cada
célula fotografada (cor do texto, do fundo, negrito), nos temas "dark", "light" e "dark-ansi".
- **No "dark-ansi" o diff não tem fundo** (só o número e o sinal coloridos) e a mensagem do dono
  tem o fundo em ANSI 8 (brightblack), que no Cadex Night é um cinza claro: as duas diferenças do
  mockup 10 vistas no dist vêm daí. Por isso o plano 33 volta ao tema de cores fixas.
- **As cores fixas** (o que o terminal troca pelas do tema, components.terminalTheme):

  | o que | "dark" | "light" |
  |---|---|---|
  | fundo da mensagem do dono / texto / ❯ | 373737 / ffffff / 999999 | f0f0f0 / 000000 / 666666 |
  | linha removida: fundo / sinal / texto | 3d0100 / dc5a5a / f8f8f2 | ffdcdc / cf222e / 333333 |
  | linha adicionada: fundo / sinal / texto | 022800 / 50c850 / f8f8f2 | dcffdc / 248a3d / 333333 |
  | ⏺ de ferramenta que terminou | 4eba65 | 2c7a39 |
  | ⏺ de ferramenta rodando, texto apagado | 999999 | 666666 |
  | o trabalhando ("✳ Flambéing…") e o mascote | d77757 | d77757 |
  | destaques do diálogo ("Bash command", ❯ 1. Yes) | b1b9f9 | 5769f7 |
  | as linhas da caixa de entrada / os tracejados | 888888 / 505050 | 8a8a8a / afafaf |
  | o modo: accept edits / plan | af87ff / 48968c | 8700ff / — |
- **O mascote:** as três primeiras linhas, colunas 0 a 9, só caracteres do bloco Unicode
  "Block Elements" (U+2580 a U+259F) em d77757, com partes de fundo 000000; o desenho muda entre
  sessões (▐▛███▜▌ e ▐▛███▛█ vistos). À direita, "Claude Code v…", o modelo e a pasta.
- **A caixa de entrada:** duas linhas inteiras de "─" (U+2500) na cor das linhas, uma acima e uma
  abaixo da linha que começa com "❯" (com um espaço sem quebra depois).
- **A linha do modo:** a última da tela, "⏵⏵ accept edits on (shift+tab to cycle)", "⏵⏵ auto mode
  on (…)", "⏸ plan mode on (…)", "⏸ manual mode on", às vezes com " · esc to interrupt" ou
  " · ← for agents" no fim. O modo vem em cor própria, o resto apagado.
- **O modo não chega ao Cadex por outro caminho na hora:** os hooks trazem `permission_mode`, mas
  só nos eventos (pedido, ferramenta, parada), e o ⇧⇥ não dispara hook; a status line roda de novo
  a cada ⇧⇥, mas o JSON dela não traz o modo. Quem sabe o modo na hora é a própria linha do modo:
  o terminal o lê de lá.
- **O que o terminal faz com isso (plano 33, fases B e C):** enquanto o Claude se reporta pelo OSC
  7501 (sem o kit também), o desenho troca as cores fixas da tabela pelas tiradas do tema do
  terminal (fundo, texto e ANSI: o fundo da mensagem do dono a 7 % do texto, o fundo do diff a 13 %
  do verde e do vermelho, o ⏺ rodando no amarelo, o trabalhando no azul); não desenha o mascote nem
  a linha do modo e põe o modo à direita da linha de cima; desenha a caixa arredondada no lugar das
  duas linhas da entrada e a mensagem do dono num bloco com cantos. Só o desenho muda: seleção,
  busca e cópia leem o texto de verdade, e o mouse vai à célula que o Claude escreveu (a caixa é
  desenhada uma linha abaixo; sem desfazer isso, o clique no meio do texto caía na borda e o cursor
  não ia, 2026-11-18). O que não bate com a medida fica como o Claude desenha; a
  dica "esc to interrupt" da linha do modo some junto com ela.
- **O pedido de permissão** é um diálogo do Claude no lugar da caixa de entrada: uma linha inteira
  de "─", "Bash command" no destaque, o comando entre duas linhas de "╌", "Do you want to
  proceed?" e as opções. Fica como o Claude desenha (o dono, 2026-11-18).

### A gaveta de terminais (mockup Drawer; plano 30 C, feito junto da revisão do plano 29)
- drawer.toggle (⌥⌘`, e o item "Terminal ⌥⌘`" da barra de status) mostra ou esconde a gaveta: terminais
  rápidos de nenhum projeto, subindo de baixo por cima do centro (entre a árvore e o painel da
  direita), 340 pt com sombra para cima; a primeira vez abre um shell na pasta pessoal.
- O topo tem as abas dela, "+" e "⌥⌘` show or hide · drag up to resize · ⌘↩ move to a task";
  arrastar a borda de cima muda a altura (de 160 até perto da barra de título). Os terminais da
  gaveta ficam sem a caixa de painel.
- drawer.move-to-project (⌘↩, só com o terminal da gaveta em foco) leva esse terminal, com o shell
  vivo, a uma aba do projeto que aparece. A última aba fechada esconde a gaveta. Não é salva entre
  aberturas do app: são terminais rápidos.

### O comando de cada terminal (plano 29, revisão contra os mockups)
- A integração do zsh manda as marcas de comando do padrão OSC 133 (C com o comando, codificado
  em URL, ao começar; D com o código de saída ao voltar o prompt), só em shell interativo, por
  add-zsh-hook (os ganchos do dono continuam). O núcleo as lê pela libghostty e guarda o comando
  que roda e o último que terminou, com o código; o app carimba a hora.
- Com isso: a aba e o cabeçalho do painel com o nome do comando ("npm run dev"), "running 38 s",
  o ponto verde e "Open :5173 in preview" no cabeçalho quando o comando mostra um endereço local
  (o clique abre o preview ao lado), a árvore com a porta ou o tempo, e a linha "make check passed
  · 2 min ago" no pé de Changes (`inspector.md`).

## Estados
- **Abrindo:** o painel aparece na hora; o prompt surge assim que o shell responde.
- **Erro ao abrir o shell** (shell configurado não existe, pasta sem permissão): o painel mostra a
  mensagem de erro e um botão para tentar com o shell padrão.
- **Sessão encerrada por erro:** o painel mostra o código de saída em vez de fechar sozinho, para não
  esconder o motivo.

## Casos de borda
- `ZDOTDIR` próprio do dono: a aba o devolve antes de ler os arquivos dele; o `zsh` aninhado vê só
  o do dono.
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
- [ ] Numa aba com zsh, `type claude` diz que é uma função; `echo $ZDOTDIR` mostra o do dono (ou
      nada); o `.zshrc` do dono rodou; com `alias claude=` no `.zshrc`, vale o alias.
- [ ] Com contraste mínimo 7, texto azul-escuro sobre fundo preto fica legível; com 1, fica como veio.
- [ ] A altura de linha e as ligaduras mudam o terminal na hora (com Fira Code, `->` vira uma seta).
- [x] Copiar um arquivo com espaço no nome no Finder e colar resulta num caminho que o shell aceita.
- [x] Colar um print de tela cola o caminho de um PNG que existe e abre a imagem.
- [x] Colar texto num programa com bracketed paste ativo não executa as linhas automaticamente.
- [ ] Colar um print no Claude Code: passar o mouse em `[Image #N]` mostra a miniatura e clicar
      abre a imagem no visualizador.
- [x] Com "copiar ao selecionar" desligado e qualquer coisa copiada, passar o mouse e selecionar
      texto no terminal não muda a área de transferência; ⌘V ainda cola o que estava lá.
- [x] Com "copiar ao selecionar" ligado, terminar uma seleção copia o texto dela.
- [x] ⌘K com o foco no terminal abre a paleta e não envia nada ao shell.
- [ ] No zsh e no bash, ⌥← ⌥→ ⌘← ⌘→ ⌥⌫ ⌘⌫ movem e apagam como descrito em Teclado.
- [ ] Em tela Retina, o texto em SF Mono 13 pt sai nítido (comparado lado a lado com o Terminal do
      macOS no mesmo tamanho).
- [x] `cat` de um arquivo de 100 MB não trava a janela, e Ctrl+C interrompe em menos de 1 segundo.
- [x] ⌘D, ⌘Shift+D, ⌘W e ⌘T funcionam e a aba nova abre na pasta da sessão ativa.
- [x] Fechar uma aba com `sleep 100` rodando pede confirmação; com o shell parado, fecha direto.
- [ ] Reabrir o app restaura abas, divisões e pastas.
- [ ] `vim`, `htop` e `less` funcionam, inclusive com rolagem e redimensionamento.
- [ ] Com terminal.keepSessions ligado, `top` rodando, fechar e reabrir o Cadex mostra o mesmo `top`
      com o scrollback; `kill -9` no app não derruba o terminal; atualizar o app mantém a sessão.
      (Conferido em 2026-11-15 com o app de release: o `top` com o mesmo pid depois do `kill -9` e o
      app reaberto religado à mesma sessão; o desenho da tela religada falta ver.)
- [x] Com terminal.keepSessions desligado, nenhum daemon roda (`ps`) e o `top` sai junto com o app.
- [ ] `printf '\e]777;notify;Build;pronto\a'` numa aba em segundo plano mostra a notificação; o
      clique leva à aba; com a aba à vista, nada aparece.
- [ ] O Claude Code numa aba recebe a resposta ao `ESC]7501;?` e manda o estado; chaves desconhecidas
      não quebram (testes do núcleo com as sequências do teste de 2026-11-14).

# status-bar

## Para que serve
Mostrar, embaixo da janela, o que quem usa quer ter sempre à vista: onde o terminal com foco está,
o ambiente e, se quiser, uso das contas, RAM, CPU, SSH e outros. Cada pessoa monta a própria barra.

## Comportamento
### Os itens
A barra tem dois lados, esquerda e direita, e cada lado é uma lista de itens em ordem. Itens:

| item | mostra | padrão |
|---|---|---|
| Folder | a trilha "Home › Cadu › Trabalho › cadex" do terminal com foco | ligado, esquerda |
| Environment | "Local" no macOS (no Windows, a distro WSL) | ligado, direita |
| Git branch | o branch do workspace, com ↑↓ de commits a enviar/receber | desligado |
| Agent usage | por conta: barra da sessão de 5 h (cresce com o espaço livre, de 40 a 88 pt), "58% 5h · 41% wk" (`agents.md`) | desligado |
| Agents | "◐ 1 · ● 2": trabalhando e esperando você | desligado |
| RAM | memória do sistema em uso: "12.4 / 16 GB" | desligado |
| CPU | uso do processador do sistema: "CPU 18%" | desligado |
| Cadex memory | a memória do próprio Cadex: "61 MB" | desligado |
| Terminals | terminais abertos: "›_ 4" | desligado |
| Ports | portas ouvindo nos processos dos terminais do Cadex: "⌁ 2 (:3000, :5173)" | desligado |
| SSH | hosts no ar: "SSH 3/3 ●" (`ssh.md`) | desligado |

Sem mexer em nada, a barra é a de sempre: trilha à esquerda e ambiente à direita.

### Personalizar
- Botão direito na barra: menu com cada item (marcado se aparece) e "Customize Status Bar…".
- "Customize Status Bar…" abre a janela Customize, a mesma da barra lateral, na aba Status Bar: as seções Left e
  Right com todos os itens, cada um com chave; arrastar uma linha reordena, e passando para a outra
  seção ela muda de lado. Os escondidos ficam embaixo do lado de costume deles.
- No ⌘K: "Customize Status Bar" e "Show or Hide a Status Bar Item" (a lista dos itens, cada um
  marcado como aparece ou escondido).
- Vale para todas as janelas na hora e fica no settings.json (statusBar.left e statusBar.right).
- Item escondido não custa nada: não mede, não vigia, não pergunta à rede.

### Folder
- Clicar num pedaço da trilha abre um menu com as subpastas daquele nível; escolher uma leva o
  terminal com foco até ela (`cd`), só se o shell estiver parado no prompt. Com um programa rodando,
  o menu mostra as pastas apagadas.
- A trilha acompanha o terminal com foco: trocar de aba ou de painel troca a pasta mostrada.

### Medidas
- RAM, CPU e Cadex memory são lidos a cada 2 s, só com o item visível e a janela na tela; com a
  janela escondida ou minimizada, param.
- Ports é lido quando um terminal abre, fecha ou um programa termina, e a cada 10 s enquanto um
  programa roda num terminal.
- Clicar em RAM, CPU ou Cadex memory abre o Monitor de Atividade; em Ports, o cartão com cada porta
  (passar o ponteiro também abre; "localhost:3000" abre no preview); em Agent usage ou Agents, a página Agents; em Git branch,
  a página Git.

## Estados
- **Pasta desconhecida** (sessão ainda abrindo): Folder fica vazio, o resto aparece.
- **Dado ainda não lido** (Agent usage antes da primeira leitura): o item mostra só o ícone, apagado.
- **Nenhum item**: a barra continua com a altura dela, vazia; o botão direito ainda abre o menu.

## Casos de borda
- Itens demais para a largura: a trilha encolhe primeiro (pedaços do meio viram "…", a pasta atual
  nunca some); depois, os itens do fim de cada lado vão para um "…" que abre a lista num menu.
- Pasta sem permissão de leitura: o menu daquele pedaço fica vazio, com "Sem acesso".
- settings.json com item desconhecido ou repetido: ignorado, vira aviso; o resto vale.

## Critérios de aceite
- [ ] Sem configuração, a barra é igual à de antes: trilha e ambiente.
- [ ] A trilha mostra a pasta do terminal com foco e muda ao trocar de aba e depois de um `cd`.
- [ ] Escolher uma subpasta no menu da trilha faz o terminal com foco ir até ela.
- [ ] Ligar RAM e CPU pelo botão direito mostra os dois na hora, em todas as janelas.
- [ ] No modo de edição, arrastar o SSH da direita para a esquerda muda o lado, e o settings.json
      guarda; reabrir o app mantém.
- [ ] Cada ação de personalizar também está no ⌘K.
- [ ] Com todos os itens novos escondidos, o `make perf` dá o mesmo de antes.

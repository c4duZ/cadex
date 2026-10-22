# agents

## Para que serve
Ver, sem sair do Cadex, os agentes de código que estão rodando (o que cada um faz, quem espera
resposta, os subagentes) e quanto do plano de cada conta já foi usado. O Cadex só observa: os
agentes continuam rodando em abas de terminal (`docs/adr/0019-agents-observe-only.md`).

## Comportamento
### Sessions
- A página Agents (as sessões) lista as sessões vivas do Claude Code de todas as contas da máquina,
  agrupadas por projeto (a raiz do repositório git da pasta da sessão, ou a própria pasta). O grupo
  mostra o nome da pasta e quantas sessões tem; clicar no título recolhe ou abre o grupo.
- Cada sessão: um sinal de estado no meio da linha do nome, o nome, há quanto tempo está naquele
  estado, uma seta e, embaixo, o logo do provedor da conta, o branch e a conta ("main · Liderhub").
  - **Trabalhando**: anel girando na cor de destaque.
  - **Esperando você**: ponto azul. O ícone Agents da barra lateral ganha o ponto também.
  - Estado desconhecido: ponto cinza, com o nome do estado na dica.
- A lista acompanha na hora: sessão nova aparece, sessão encerrada some, estado muda, sem botão de
  atualizar.
- Clicar numa sessão (ou na seta) abre ou fecha os subagentes dela, desdobrando em 0,2 s (a seta
  gira junto): "4 subagents" e uma linha por subagente,
  com sinal (girando se escreveu nos últimos 30 s, senão ✓), a descrição e há quanto tempo. No
  máximo 10, os mais recentes primeiro.
- Duplo clique numa sessão que roda num terminal do Cadex foca esse terminal em qualquer janela,
  trazendo a janela para a frente e trocando de space e de aba se preciso; clique num subagente leva
  ao terminal da sessão dele (o terminal certo é o que tem o processo da sessão na frente). Sessão de fora do
  Cadex (outro terminal) mostra "outside Cadex" e o duplo clique mostra a pasta dela na árvore do
  explorer, quando ela está no workspace.
- As linhas acendem ao passar o ponteiro (0,12 s) e escurecem ao apertar: o clique responde antes
  de a ação acontecer. Antes o ponto ficava acima do nome e nada se mexia (o dono achou travado,
  2026-10-21); o clique indo ao terminal foi testado e desfeito no mesmo dia.
### Conversa do subagente
- Clicar num subagente (rodando ou já terminado) abre a conversa dele numa aba só de leitura, ao
  lado ou em aba nova como os arquivos (general.openFiles); de novo, vai à aba que já existe. Só
  abre por esse clique: não há comando nem atalho (o dono, 2026-10-21).
- O jeito é o do Claude Code no terminal, na fonte monoespaçada: a tarefa e as mensagens depois de
  "> " num fundo suave; as respostas com "●" e o Markdown delas (negrito, código, títulos, listas);
  cada ferramenta como "● Bash(make test)" e embaixo "⎿" com as três primeiras linhas do que voltou
  e "… +N lines" (em vermelho se falhou); um Edit mostra as linhas que saem em vermelho e as que
  entram em verde. O raciocínio e as marcas do Esc ficam de fora.
- Enquanto o subagente escreve, a aba acompanha: o sistema avisa que o arquivo cresceu e só o trecho
  novo é lido; se a vista estava no fim, ela desce junto.
- Peso: o log é lido em pedaços de 256 KB fora da linha principal; um resultado longo nunca é
  guardado (os primeiros 4 KB dão a prévia, as linhas são contadas enquanto os bytes passam). Uma
  vista de texto só, que desenha só o que aparece. Fechada a aba, nada fica: nenhuma leitura,
  nenhum arquivo vigiado. O `make perf` abre um log de 34 MB e confere aberto e fechado.
- Depois: a aba de terminal com um agente mostra o mesmo sinal de estado no título.

### Accounts
- A página Accounts, com ícone próprio na barra lateral (o medidor), mostra um cartão por conta: o nome (a organização da conta; renomeável), o
  plano, e duas barras: a sessão de 5 horas e a semana, com a porcentagem e quando reinicia.
- A barra fica na cor de alerta a partir de 70% e na de perigo a partir de 90%.
- Conta é cada pasta de configuração do Claude Code na pasta pessoal (`~/.claude` e as
  `~/.claude-*`) e cada uma do Codex (`~/.codex` e as `~/.codex-*` com login, pelo e-mail do
  login). Achar as contas não pede configuração. Cada cartão tem o logo do provedor
  (`docs/adr/0020-provider-logos.md`).
- O uso do Codex vem dos logs do próprio Codex (os limites que ele grava a cada uso), sem
  requisição nem token: é o número do último uso, com "em <hora>"; janela que já reiniciou desde
  então mostra 0%.
- O item Agent usage da barra de status mostra a conta do agente que roda no terminal com foco (o
  Claude Code pela sessão, o Codex pelo nome do programa); sem agente, a última mostrada. O ponteiro
  sobre ele abre um popover com todas as contas de todos os provedores, com plano, sessão e semana.
- O uso é lido a cada 5 minutos, só enquanto alguém o mostra (a página Accounts ou o item da barra
  de status) e com o app ativo. Abrir a página com o dado vencido lê na hora. "Refresh" no menu do
  cartão e no ⌘K ("Agents: Refresh Usage").
- O Cadex só lê o login que o Claude Code guardou. Nunca renova, troca ou grava o login.

### Notificações
- Quando uma sessão que trabalhava passa a esperar você, o Cadex manda uma notificação do sistema,
  escrita como as dos terminais e ferramentas de agente: o tipo no título, com o nome do agente
  (Claude ou Codex, pela conta): "Claude Wants to Run a Command" (Bash), "… to Edit a File"
  (Edit, Write), "… to Use <ferramenta>", "Claude Has a Question", "Claude Finished". O subtítulo é
  projeto · sessão · conta; o texto, o detalhe: o comando ou o arquivo, a pergunta (ou "A plan is
  ready for your review"), a primeira linha da última resposta.
- O motivo vem do fim do log da conversa (os últimos 64 KB), lido uma vez por parada: a última
  ferramenta pedida sem resposta é uma permissão, a de pergunta é uma pergunta, o fim de turno é
  "terminou". Sem dizer, "Stopped and waits for you", contado como pergunta.
- Sem imagem: à esquerda fica o ícone do Cadex, que o macOS não deixa trocar por notificação (só
  as de comunicação, com permissão paga da Apple, mostram a foto de quem mandou; a API privada do
  terminal-notifier saiu dele), e a imagem à direita, com o símbolo do tipo, destoava (o dono,
  2026-10-22, depois de pesquisa).
- Cada tipo toca o seu som, escolhido em Configurações › General ao lado da chave dele: um som do
  macOS (padrão: Funk, Ping e Glass), o alerta padrão, nenhum, ou um arquivo seu (.aiff, .wav,
  .caf); escolher toca o som. O macOS toca o som com a notificação (o Foco e a chave de som do
  Cadex nos Ajustes valem): o Cadex copia o escolhido para `~/Library/Sounds` como "Cadex
  Permission" (Question, Finished), onde o sistema procura os sons de um app fora de sandbox.
- Ao ir ao terminal de um agente, a notificação dele sai da Central de Notificações.
- Clicar leva ao terminal do agente, trazendo a janela, o space e a aba. Não avisa enquanto você
  olha aquele terminal na janela da frente. Uma notificação por sessão: a nova troca a anterior.
- Três chaves, cada tipo desligável sozinho: agents.notifyPermission, agents.notifyQuestion e
  agents.notifyFinished, ligadas por padrão; com agents.sessions desligado, nenhuma. Os sons em
  agents.soundPermission, agents.soundQuestion e agents.soundFinished ("none", "default", o nome de
  um som do macOS ou o caminho de um arquivo).
- "Send Test Notifications" (agents.test-notifications, no ⌘K) manda as três de exemplo; com as
  notificações do Cadex desligadas no macOS, abre a página dele nos Ajustes do Sistema.
- Qualquer estado depois de trabalhando conta como parada (idle, waiting e shell, este o de um
  turno que acabou de terminar, visto ao vivo em 2026-10-21); o fim do log diz o motivo, lido 1 s
  depois da parada (o estado muda antes de o log receber a marca do Esc) e nada se voltou a trabalhar.
- Parada por você (Esc; o log termina com "[Request interrupted by user…]") não avisa: você sabe
  que parou (o dono, 2026-10-21).
- Só no Mac por enquanto; no Windows chega com o port (lá dá para trocar o ícone da notificação).

### Configurações
- Três chaves, cada uma desliga uma leitura por inteiro (nada vigiado, nenhuma requisição):
  agents.sessions, agents.accounts e, em ssh, ssh.ping. Ligadas por padrão.
- Accounts tem a cara do cartão do item de uso: um bloco por conta (logo, nome, "· plano", as
  barras), com espaço largo entre eles e sem linha nem caixa; a pasta fica na dica.
- Conta sem login, ou com login vencido há mais de um dia, não aparece em Accounts, no item de uso
  nem no cartão; vencido há menos (o Claude Code renova enquanto a conta é usada) aparece com o aviso.
- Clicar numa conta com o agente dela já rodando num terminal do Cadex vai a esse terminal (o usado
  por último, se há vários; em qualquer janela), sem abrir outro.
- Sem nenhum, clicar abre o agente dela (ADR 0019): no terminal com foco, se ele está no prompt, ou
  numa aba nova na pasta dele, digita `claude` com `CLAUDE_CONFIG_DIR` da conta (ou `codex` com
  `CODEX_HOME`) e Enter; com agents.launchSkipPermissions, sem pedir permissões. Também no ⌘K ("Open
  an Account's Agent") e no clique direito.
- Esconder uma conta (clique direito, ou a chave em Customize › Accounts; agents.hiddenAccounts) a
  tira de Accounts, do item e do cartão (as sessões dela continuam em Sessions) e ela não é lida.
  Ela volta sozinha quando o login dela muda (novo login, renovação por uso; guardado em
  agents.hiddenLogins na hora de esconder, conferido a cada 5 min com alguém olhando), nunca por um
  reinício de janela. Customize › Accounts lista todas, com o estado de cada uma, e a opção "Without
  permission prompts".
- Renomear (agents.accountNames, pelo botão direito no cartão): o nome novo vale em Sessions, nas
  notificações e na barra de status; vazio volta ao da organização.
- agents.accounts desliga a leitura do uso: nenhum login lido, nenhuma requisição.
- O Cadex se identifica como Cadex na requisição; com isso o serviço respondeu 200 nas três contas
  do dono (2026-10-21). Um 429 espera o que o serviço pedir.

## Estados
- **Nenhum agente rodando**: "No agents running. Start one in a terminal: claude".
- **Claude Code não instalado ou nenhuma conta**: a página diz isso e Accounts fica vazia, sem erro.
- **Login vencido**: o cartão diz "Login expired. Run claude with this account to renew it." e a
  barra de status esconde a conta.
- **Sem rede ou erro do serviço**: o cartão mantém o último valor, apagado, com "updated 12 min ago";
  tenta de novo com espera crescente (5, 10, 20 min, até 1 h).
- **Leitura desligada**: a página explica qual chave está desligada, com o botão para ligar.

## Casos de borda
- O formato dos arquivos do Claude Code mudou (versão nova): o que não der para ler é pulado, a
  página mostra o que conseguiu e nada trava. Um aviso discreto: "Some sessions could not be read".
- Processo morto deixou o registro da sessão para trás: a sessão não aparece (conferido a cada 10 s
  enquanto alguém olha).
- Conta nova, sem nenhuma sessão ainda: a pasta sessions dela entra na conferência de 10 s.
- Duas contas da mesma organização: o nome ganha a pasta ("BKDG · bkdg").
- Duas sessões na mesma pasta: as duas aparecem no mesmo grupo, cada uma com o próprio estado.
- Muitas sessões (mais de 50): a lista rola e só as linhas na tela são desenhadas.
- Pedido negado pelo serviço por excesso (429): espera o tempo pedido antes de tentar de novo.

## Critérios de aceite
- [ ] Rodar `claude` numa aba faz a sessão aparecer em até 1 s, no projeto certo, com a conta certa.
- [ ] Mandar uma mensagem troca o sinal para "trabalhando"; quando o agente termina, "esperando você".
- [ ] Fechar a aba do agente tira a sessão da lista.
- [ ] Os subagentes de uma sessão aparecem ao clicar, com descrição e tempo.
- [ ] Com duas contas logadas, Accounts mostra as duas com os mesmos números do `/usage` de cada uma.
- [ ] Conta com login vencido mostra o aviso e não faz requisição a cada 5 min.
- [ ] Com agents.sessions e agents.accounts desligados, o Cadex não abre nenhum arquivo do Claude
      Code nem faz nenhuma requisição (conferido com `fs_usage` e `nettop`).

# agents

## Para que serve
Ver, sem sair do Cadex, os agentes de código que estão rodando (o que cada um faz, quem espera
resposta, os subagentes) e quanto do plano de cada conta já foi usado. O Cadex só observa: os
agentes continuam rodando em abas de terminal (`docs/adr/0019-agents-observe-only.md`).

## Comportamento
### Sessions
- A página Agents › Sessions lista as sessões vivas do Claude Code de todas as contas da máquina,
  agrupadas por projeto (a raiz do repositório git da pasta da sessão, ou a própria pasta). O grupo
  mostra o nome da pasta e quantas sessões tem.
- Cada sessão: um sinal de estado, o nome da sessão, há quanto tempo está naquele estado e, embaixo,
  o branch e a conta ("main · Liderhub").
  - **Trabalhando**: anel girando na cor de destaque.
  - **Esperando você**: ponto azul. O ícone Agents da barra lateral ganha o ponto também.
  - Estado desconhecido: ponto cinza, com o nome do estado na dica.
- A lista acompanha na hora: sessão nova aparece, sessão encerrada some, estado muda, sem botão de
  atualizar.
- Clicar numa sessão abre ou fecha os subagentes dela: "4 subagents" e uma linha por subagente,
  com sinal (girando se escreveu nos últimos 30 s, senão ✓), a descrição e há quanto tempo. No
  máximo 10, os mais recentes primeiro.
- Duplo clique numa sessão que roda num terminal do Cadex foca esse terminal, trocando de aba e de
  space se preciso (o terminal certo é o que tem o processo da sessão na frente). Sessão de fora do
  Cadex (outro terminal) mostra "outside Cadex" e o duplo clique mostra a pasta dela na árvore do
  explorer, quando ela está no workspace.
- Depois: a aba de terminal com um agente mostra o mesmo sinal de estado no título.

### Accounts
- Agents › Accounts mostra um cartão por conta: o nome (a organização da conta; renomeável), o
  plano, e duas barras: a sessão de 5 horas e a semana, com a porcentagem e quando reinicia.
- A barra fica na cor de alerta a partir de 70% e na de perigo a partir de 90%.
- Conta é cada pasta de configuração do Claude Code na pasta pessoal (`~/.claude` e as
  `~/.claude-*`). Achar as contas não pede configuração.
- O uso é lido a cada 5 minutos, só enquanto alguém o mostra (a página Accounts ou o item da barra
  de status) e com o app ativo. Abrir a página com o dado vencido lê na hora. "Refresh" no menu do
  cartão e no ⌘K ("Agents: Refresh Usage").
- O Cadex só lê o login que o Claude Code guardou. Nunca renova, troca ou grava o login.

### Notificações
- Quando uma sessão que trabalhava passa a esperar você, o Cadex manda uma notificação do sistema
  dizendo por quê: "Asks permission to run Bash", "Asked you a question" (também um plano para
  aprovar) ou "Finished". O título é o projeto e a conta; o texto, o motivo e o nome da sessão.
- O motivo vem do fim do log da conversa (os últimos 64 KB), lido uma vez por parada: a última
  ferramenta pedida sem resposta é uma permissão, a de pergunta é uma pergunta, o fim de turno é
  "terminou". Sem dizer, "Stopped and waits for you", contado como pergunta.
- Cada tipo tem a sua imagem ao lado do texto (cadeado com chave, interrogação, ✓), branca na cor de
  destaque do tema; o ícone à esquerda é o do app, que o macOS não deixa trocar.
- Clicar leva ao terminal do agente, trazendo a janela, o space e a aba. Não avisa enquanto você
  olha aquele terminal na janela da frente. Uma notificação por sessão: a nova troca a anterior.
- Três chaves, cada tipo desligável sozinho: agents.notifyPermission, agents.notifyQuestion e
  agents.notifyFinished, ligadas por padrão; com agents.sessions desligado, nenhuma.
- "Send Test Notifications" (agents.test-notifications, no ⌘K) manda as três de exemplo; com as
  notificações do Cadex desligadas no macOS, abre a página dele nos Ajustes do Sistema.
- Qualquer estado depois de trabalhando conta como parada (idle, waiting e shell, este o de um
  turno que acabou de terminar, visto ao vivo em 2026-10-21); o fim do log diz o motivo.
- Só no Mac por enquanto; no Windows chega com o port (lá dá para trocar o ícone da notificação).

### Configurações
- Três chaves, cada uma desliga uma leitura por inteiro (nada vigiado, nenhuma requisição):
  agents.sessions, agents.accounts e, em ssh, ssh.ping. Ligadas por padrão.
- Esconder uma conta (agents.hiddenAccounts) a tira de Accounts e do item de uso (as sessões dela
  continuam em Sessions); ela fica no fim de Accounts, apagada, com "Show", e não é lida.
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

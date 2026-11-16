# 0034 — Automações agendadas rodam no app, acordado por um LaunchAgent

Data: 2026-11-16 · Status: aceita · Apoia-se em `docs/adr/0033-cadex-launches-agents.md` (o Cadex
abre agentes com prompt) · Não muda `docs/adr/0022-terminal-daemon.md` · Plano
`docs/plans/24-many-agents.md`, fase E

## Contexto
O dono quer um prompt que rode sozinho num horário (dias úteis 09:00, a cada 4 horas, uma vez),
numa worktree nova ou fixa, com conta, modelo e teto escolhidos, mesmo com o Cadex fechado
(2026-11-14). Alguém tem de acordar no horário, montar o kit da sessão, abrir a aba e guardar o
histórico.

O que já existe:
- o daemon do terminal (ADR 0022) é dono dos PTYs, desligado por padrão, sai sozinho sem sessão e
  não tem timer; não conhece contas, kit, worktrees nem o estado da orquestração, que moram no app;
- a ADR 0022 recusou um LaunchAgent para o daemon porque um job com KeepAlive o reiniciaria e
  porque o macOS avisa "item em segundo plano adicionado"; para uma automação, que o dono liga de
  propósito para rodar sem ele, o aviso é o esperado;
- o launchd roda um job de `StartCalendarInterval` perdido durante o sono assim que o Mac acorda
  (os disparos perdidos viram um), e não roda o que se perdeu com o Mac desligado;
- a feature `power` já segura o sono do sistema com um pedido de energia (`docs/spec/power.md`).

## Decisão
- **A automação roda no app, não no daemon.** É o app que monta o kit (ADR 0021), cria a worktree
  (plano 19), abre a aba com o prompt (ADR 0033) e grava a execução no estado da orquestração. O
  daemon do terminal continua só dos PTYs (ADR 0022 sem mudança); com terminal.keepSessions ligado,
  a aba da automação é mantida por ele como qualquer outra.
- **Um LaunchAgent só para acordar o app.** Um plist em `~/Library/LaunchAgents/` (nome do bundle
  mais `.automations`), escrito pelo app e carregado com `launchctl bootstrap gui/<uid>`:
  - **instalado só quando a primeira automação é ligada e removido com a última** (e quando
    orchestration.automations é desligada); sem automação ligada, nenhum plist existe;
  - `StartCalendarInterval` com os horários de todas as automações ligadas (uma lista de datas do
    launchd), reescrito e recarregado quando uma automação muda; sem `KeepAlive`, sem `RunAtLoad`
    e sem `StartInterval`: nada roda fora dos horários;
  - o programa do job é o `cadex` do bundle (`cadex automations due`), que pede ao app, pelo
    `app.sock`, que confira a agenda; com o app fechado, abre o Cadex em segundo plano (sem janela
    na frente, sem roubar o foco, como o `CADEX_BACKGROUND=1`) e sai.
- **O pedido "confira a agenda" não carrega nada.** É uma espécie nova de pedido no `app.sock`,
  aceita só do mesmo usuário (`getpeereid`) e sem token de sessão, porque não diz o que rodar: o app
  só olha a própria agenda e roda o que já estava ligado e vencido. Um processo qualquer do usuário
  pode no máximo adiantar a conferência.
- **O app confere a agenda ao abrir e ao acordar do sono**, além do pedido do job: o que venceu e
  não rodou é uma **execução perdida**. Cada automação diz o que fazer com ela: rodar uma vez ao
  acordar (o padrão) ou pular, registrada como "pulada". Várias perdidas da mesma automação viram
  uma. Desligado o Mac, a regra é a mesma na próxima abertura.
- **Sem timer no app.** Entre um horário e outro o app não acorda por relógio: quem marca a hora é
  o launchd. Com o app aberto, o pedido do job chega pelo socket.
- **Acordado durante a execução.** Enquanto uma automação roda, o app pede ao sistema para não
  dormir pela porta de entrada da feature `power` (orchestration.keepAwakeDuringRuns, ligada) e
  solta ao terminar ou bater no teto. O Cadex não acorda o Mac do sono para rodar (`pmset` pede
  root); a execução perdida cobre isso.
- **Sem servidor fora da máquina.** Nada de nuvem, cron remoto ou serviço da Anthropic agendando: a
  automação existe neste Mac. Automação em outra máquina depende do "Rodar em" completo (ADR 0031).
- **Tetos e termos como na ADR 0033:** cada execução tem teto de gasto e de duração; a automação
  nova sugere a chave de API pelo `apiKeyHelper`, e usar a assinatura é escolha do dono por
  automação.

## Alternativas recusadas
- **Rodar a automação no daemon do terminal:** o daemon teria de conhecer contas, kit, worktrees e o
  banco da orquestração, e passaria a viver sem sessão nenhuma, esperando um horário: o oposto do
  "pequeno e sem timer" da ADR 0022.
- **Um timer no app** (a cada minuto ver se algo venceu): custa com o app aberto e não roda com ele
  fechado.
- **SMAppService com o plist no bundle:** o plist fica fixo dentro do app assinado, e os horários
  mudam com cada automação.
- **`KeepAlive` ou `StartInterval` no job:** acordaria um processo a cada intervalo, com ou sem
  automação vencida.
- **cron (`crontab`):** não roda o perdido no sono, e escrever na crontab do dono mexe numa
  configuração que não é do Cadex.
- **Acordar o Mac com `pmset schedule`:** pede root e acorda a máquina inteira do dono sem ele ver.

## Consequências
- `docs/spec/orchestration.md` (Automações) e `docs/spec/power.md` (a porta de entrada que a
  automação usa). Plano 24, fase E.
- Ligar a primeira automação faz o macOS mostrar o aviso de item em segundo plano; a tela de ligar
  diz isso antes.
- O `make perf` confere que, sem automação ligada, nenhum plist existe e nada do launchd é do Cadex
  (`launchctl print gui/<uid>`).
- Propor rodar automação no daemon, um timer no app ou um LaunchAgent instalado sem automação
  ligada é desfazer esta decisão.

# 0021 — Contas gerenciadas pelo Cadex, uso sem token e abrir o agente sem prompt

Data: 2026-11-14 · Status: aceita, revista em parte por `docs/adr/0028-project-memory.md` (os
hooks do kit vão por `--plugin-dir`) · Revê em parte `docs/adr/0019-agents-observe-only.md`

## Contexto
Depois do estudo "Cadex × Claude Code" (2026-11-14), o dono decidiu que o Cadex passa a ser dono
da sessão do agente: o Claude Code continua o motor, e o Cadex abre as sessões, escolhe a conta,
guarda o histórico de todas e deixa continuar uma conversa em outra conta quando o limite acaba
(`docs/plans/18-accounts-and-sessions.md`). A ADR 0019 tinha decidido o contrário em três pontos:
o login lido do Keychain a cada leitura de uso, o uso pedido ao serviço com esse token, e "a única
coisa que o Cadex inicia" sendo o agente de uma conta, num clique.

Dois fatos mudaram o quadro:
- **Os termos da Anthropic** dizem que desenvolvedores "may not collect, store, or intermediate
  Claude.ai credentials or session tokens" (code.claude.com/docs/en/legal-and-compliance, lido em
  2026-11-14). Ler o token do Keychain e repassá-lo ao serviço de uso é intermediar credencial,
  mesmo sem guardar.
- **Os testes de 2026-11-14** (Claude Code 2.1.325, 24 itens, conta de teste) mostraram caminhos
  sem token:
  - a status line recebe `rate_limits.five_hour` e `.seven_day` (`used_percentage`, `resets_at`),
    `context_window`, `cost`, `session_id` e `transcript_path`: o mesmo número do `/usage`;
  - hooks passados por `--settings` **se somam** aos da conta e do projeto (os do GSD seguem
    rodando); o `statusLine` do `--settings` **substitui** o da conta;
  - `--plugin-dir` carrega skills e `--mcp-config` carrega MCPs sem escrever em configuração;
  - uma pasta de conta com links para `skills/`, `settings.json` e `CLAUDE.md` de outra carrega
    tudo;
  - `claude --resume <caminho do .jsonl> --fork-session` com outra `CLAUDE_CONFIG_DIR` continua a
    conversa na outra conta, grava a cópia nela e deixa o original intacto (mesmo hash); sem
    `--fork-session`, a outra conta escreve no arquivo da primeira;
  - a validade do login (`credential_expires_at`) só aparece no `result` de um `claude -p`.

## Decisão
- **O Cadex cria e gerencia pastas de conta.** Conta nova nasce em
  `~/Library/Application Support/Cadex/accounts/<nome>` (caminho curto: sockets têm limite de
  tamanho de caminho), e o login é feito pelo próprio `claude` (`/login`) numa aba. As contas que já
  existem (`~/.claude`, `~/.claude-*`) **ficam onde estão**: no Mac o login está no Keychain amarrado
  ao caminho da pasta, e mover desloga.
- **Configuração compartilhada por link.** `~/.claude` é a conta padrão e a fonte; a conta
  gerenciada recebe link de tudo o que existe no topo da fonte, **menos o estado da conta**
  (`.claude.json`, `projects/`, `sessions/`, `history.jsonl`, `jobs/`, `daemon/`, `state/`,
  `file-history/`, `paste-cache/`, `shell-snapshots/`, `cache/`, `backups/`, `downloads/`,
  `feedback/`, `session-env/`, `stats-cache.json`, `daemon-*`, `.last-*`). Lista negra, não branca:
  o que uma ferramenta instala na pasta (como o GSD) segue funcionando. Nas contas de hoje, ligar a
  configuração compartilhada é opcional, mostrado antes, e o que já existe vai para a lixeira.
- **Kit da sessão.** Toda sessão que o Cadex abre recebe dele `--settings`, `--plugin-dir`,
  `--mcp-config` e o ambiente da aba (o `cadex` no PATH, `CLAUDE_CONFIG_DIR` da conta, e o herdado
  limpo: sem `CLAUDECODE` nem `CLAUDE_CODE_*`, que num teste desligaram o transcript). É a única
  porta pela qual o Cadex põe status line, hooks e MCP numa sessão. Os MCPs da conta padrão são
  lidos (só leitura) e repassados pelo `--mcp-config`.
- **Uso pelo `rate_limits` da status line.** O comando da status line do kit (`cadex statusline`)
  grava por conta o `rate_limits` e por sessão o `context_window` e o `cost`, e roda a status line
  que o dono já tem, imprimindo a saída dela. Sem sessão aberta pelo Cadex na conta, o cartão mostra
  o último valor com a hora.
- **Nunca token.** O Cadex deixa de ler o Keychain (sai o `/usr/bin/security`) e deixa de chamar o
  serviço de uso. Não lê, guarda, renova nem repassa credencial, e não fala com a API da Anthropic.
  "Conta com login" passa a ser o `oauthAccount` no `.claude.json` dela (só leitura); "login
  vencido" é uma sessão que falhou com erro de autenticação, ou o `credential_expires_at` de um
  `claude -p` que o Cadex já rode por outro motivo. O Cadex não roda `-p` só para isso.
- **Não escrever na configuração do Claude Code.** Nada no `.claude.json` de conta nenhuma (o
  Claude Code o regrava com a sessão aberta) nem no `~/.claude` do dono, fora os links pedidos nas
  pastas que o Cadex cria. O que o Claude grava num arquivo lincado atravessa o link e vale para
  todas as contas; a spec diz isso.
- **O que o Cadex inicia, ampliado.** Além de abrir o agente de uma conta (ADR 0019), o Cadex abre o
  agente **sem prompt** em:
  - Retomar uma sessão do histórico (`claude --resume <id>` na conta dona) e Continuar em outra
    conta (`claude --resume <caminho> --fork-session` na outra; o fork é obrigatório);
  - Nova tarefa e relançar depois de hibernar (plano 19).
  Em todos, como antes: digitar um comando numa aba de terminal. O Cadex continua sem mandar prompt,
  sem escolher modelo, sem ler resposta e sem chat embutido. Mandar prompt é decisão de outra ADR
  (a 0033, do plano 24).
- **O histórico lê o formato do Claude Code no app, em Swift**, como a ADR 0019 decidiu, com a
  mesma defesa (campo que falta é pulado), lendo só o que foi acrescentado a cada arquivo e nunca
  guardando resultado de ferramenta. A busca em texto usa o SQLite do sistema com FTS5 (conferido
  no `/usr/bin/sqlite3` 3.54 do macOS em 2026-11-14), sem dependência nova (ADR 0007).

### O que muda na ADR 0019
- **"Login só de leitura"** sai: o Cadex não lê login nenhum.
- **A leitura do uso pelo serviço** sai, junto com "Sem fingir ser outro programa" na parte das
  requisições, que deixam de existir. O Cadex continua se identificando como Cadex onde aparecer.
- **"A única coisa que o Cadex inicia"** passa a ser a lista acima.
- O resto continua valendo: o Cadex observa as sessões pelo que o Claude Code grava, lê o fim do log
  só numa parada, abre a conversa de um subagente só num clique, tudo desligável e com custo zero
  desligado.

## Alternativas recusadas
- **Continuar lendo o token só para o uso:** contra os termos citados acima.
- **Mover as contas de hoje para a pasta do Cadex:** desloga cada uma (o login no Keychain segue o
  caminho da pasta).
- **Lista branca do que compartilhar:** quebraria ferramentas instaladas na pasta (o GSD) e cada
  item novo do Claude Code exigiria uma versão nova do Cadex.
- **Escrever status line e hooks no `settings.json` das contas:** mexeria em sessões abertas fora do
  Cadex e no arquivo do dono; o `--settings` faz o mesmo só nas sessões do Cadex.
- **`CLAUDE_CODE_PROJECT_DIR_NAME`:** funciona (teste de 2026-11-14), mas sessões abertas fora do
  Cadex iriam para outra pasta do mesmo projeto.
- **Rodar `claude -p` periodicamente para ler a validade do login:** gasta uso da conta só para
  isso.
- **Copiar o comportamento do Orca pelo código:** ADR 0004; vem da documentação dele e dos testes.

## Consequências
- Spec: `docs/spec/agents.md` (Contas gerenciadas, Histórico e o uso sem token). Plano 18, fases B a
  E; os planos 19, 20 e 24 apoiam-se no kit da sessão e na lista do que o Cadex inicia.
- Sessão aberta fora do Cadex não informa o uso; o cartão diz "Abra o agente pelo Cadex para ver o
  uso".
- O aviso de login vencido fica menos preciso: aparece quando uma sessão falha, não antes.
- Uma versão nova do Claude Code pode mudar a status line, os nomes do estado da conta ou o formato
  dos transcripts; a lista negra e o leitor do histórico acompanham, e o que não der para ler é
  pulado.

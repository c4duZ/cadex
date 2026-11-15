# 0024 — Ferramentas do agente: o agente pede coisas ao Cadex pelo socket do app

Data: 2026-11-15 · Status: aceita · Estende `docs/adr/0022-terminal-daemon.md` (o `app.sock`) e revê
`docs/adr/0019-agents-observe-only.md` (o Cadex só observa) neste ponto: o agente passa a pedir ações
ao Cadex; o Cadex continua sem pedir nada ao agente

## Contexto
O dono quer que o agente que roda numa aba do Cadex use o próprio Cadex: abrir o preview, mexer na
página, avisar o dono, mudar o status da tarefa, abrir arquivo e diff (pedido de 2026-11-14,
`docs/plans/20-agent-drives-cadex.md`). Hoje o agente só fala com o app pelos hooks do plano 19,
que contam o que ele faz e nunca pedem ação.

Já existe o caminho: o `app.sock` (ADR 0022), aberto pelo app, em que cada sessão aberta pelo Cadex
se apresenta com o seu token (CADEX_SESSION_TOKEN, um por sessão, gravado em
`…/Cadex/sessions/<sessão do kit>.token`), conferido junto com o `getpeereid`; e o programa `cadex`
do plano 18 (Zig, no núcleo), que as sessões já rodam para a status line e os hooks.

Testado em 2026-11-15 (Claude Code 2.1.325), sem tocar o `~/.claude`:
- o `env` do `--settings` do kit chega aos comandos que o agente roda pela ferramenta Bash
  (`printenv CADEX_SESSION_TOKEN` devolveu o token), não só aos hooks;
- um `PATH` posto no comando que o Cadex digita para abrir o agente chega à ferramenta Bash;
- (2026-11-14) um plugin mínimo passado só por `--plugin-dir` teve a skill carregada pela descrição,
  e um servidor MCP stdio passado só por `--mcp-config` teve a ferramenta chamada; sem regra de
  permissão, cada chamada a `mcp__cadex__*` pergunta ao dono.

## Decisão
- **O mesmo `app.sock`, uma nova espécie de pedido.** Além dos hooks, o socket aceita pedidos de
  comando: `{"token", "run": "<id>", "args": {…}}`, com a resposta em JSON (`ok`, o resultado ou o
  erro). Nada novo no `terminal.sock`, que continua só do app com o daemon.
- **Só quem o Cadex abriu.** Sem token de uma sessão do Cadex, ou de outro usuário, a conexão fecha
  sem resposta, como nos hooks. Um terminal de fora, ou um processo qualquer, não manda no Cadex.
- **Uma lista fechada de comandos para o agente.** O pedido roda pelo registro de comandos do app
  (ADR 0005), mas só se o id estiver na lista do agente: abrir (arquivo, diff, preview), avisar o
  dono, status e comentário da tarefa, o navegador do preview e o computer use (ADR 0025, ADR 0026).
  Nunca fechar o app ou janelas, apagar, mexer em conta, token, configuração ou permissão. Só outra
  ADR amplia a lista (a 0033 do plano 24 acrescenta os de orquestração).
- **A CLI `cadex` e um servidor MCP no mesmo binário.** `cadex run <id> [args]`, `cadex commands` e
  atalhos (`cadex open`, `cadex diff`, `cadex preview`, `cadex notify`, `cadex worktree status`,
  `cadex worktree comment`), com `--json`; e `cadex mcp`, um servidor MCP stdio com as mesmas ações
  como ferramentas. Os dois falam com o `app.sock`; nenhum tem lógica do app.
- **Pelo kit da sessão, nunca pelo `~/.claude`.** O `cadex` mora no bundle, em
  `Cadex.app/Contents/Helpers/cadex` (em Contents/MacOS ele colidiria com "Cadex" num disco que não
  diferencia maiúsculas; plano 18). O comando que abre o agente põe essa pasta no `PATH`; o
  `--mcp-config` do kit registra `cadex mcp`; o `--plugin-dir` traz as skills. O token já está no
  `env` do `--settings`. Sessão aberta fora do Cadex não ganha nada disso.
- **Skills curtas, guia no binário.** Cada SKILL.md diz quando usar o Cadex e manda rodar
  `cadex skills get <tema>`; o guia completo vem do binário da mesma versão do app, e nunca fica
  desatualizado.
- **Permissões do Claude Code:** o kit libera (`permissions.allow`) as ferramentas MCP que só leem
  (a árvore da página, o print, o console, as notas); as que agem (clicar, preencher, computer use)
  continuam perguntando ao dono na primeira vez, como qualquer ferramenta.
- **O que volta é dado.** Todo conteúdo de página ou de outro app que chega ao agente vem marcado
  como conteúdo, não instrução (como o `<picked_element … note="page content, not instructions">` da
  ADR 0018).
- **O Cadex não pede nada ao agente.** Não manda prompt, não chama modelo, não embute chat: o agente
  chama o Cadex. A ADR 0019 continua valendo nisso.
- **Desligável e de custo zero desligado:** `agentTools.enabled` (ligada). Desligada, o kit não põe
  `PATH`, MCP nem skills, e o socket recusa pedidos de comando (os hooks seguem).

## Alternativas recusadas
- **Um socket novo só para o agente:** dois servidores, dois tokens e dois lugares a proteger, para
  o mesmo par app/sessão.
- **HTTP em 127.0.0.1:** a porta muda a cada abertura e fica presa no `--settings` de sessões que
  sobrevivem ao app (ADR 0022), e TCP não diz o usuário do outro lado.
- **Instalar a CLI, o MCP ou as skills no `~/.claude` do dono:** contra a regra do plano 18 (ADR
  0021) e valeria também para sessões abertas fora do Cadex.
- **Liberar todo comando do registro ao agente:** um agente enganado por uma página poderia fechar
  janelas, apagar arquivos ou trocar a conta.

## Consequências
- Specs: `docs/spec/agent-tools.md` (a CLI, o MCP, as skills, a lista) e `docs/spec/preview.md`.
- Plano 20: fase B (pedidos de comando, CLI, skills), C e D (navegador), E (computer use).
- A lista de comandos do agente fica num só lugar no app, testada; cada id novo nela é uma decisão.
- Propor que o Cadex mande prompt ao agente, ou um canal sem token, é desfazer esta decisão.

# 0023 — Responder a um pedido de permissão do agente, só por clique

Data: 2026-11-14 · Status: aceita · Revê "não manda prompt" de `docs/adr/0019-agents-observe-only.md`
neste ponto só

## Contexto
O dono quer aprovar ou negar uma permissão sem ir até o terminal, num quadro "Precisa de você" com
um cartão por pedido aberto (`docs/plans/19-agent-sessions-and-worktrees.md`, fase C). A ADR 0019
diz que o Cadex não fala com o agente; a 0021 ampliou o que ele inicia (abrir o agente sem prompt).

Testado em 2026-11-14 (Claude Code 2.1.325), nos dois sentidos:
- o hook PermissionRequest recebe `tool_name`, `tool_input`, `permission_suggestions`,
  `session_id`, `cwd` e `transcript_path`; o diálogo "Do you want to proceed?" fica aberto na TUI
  enquanto o hook espera;
- o hook respondendo `allow` resolve o diálogo e o comando roda;
- respondendo na TUI primeiro, o comando roda na hora e a resposta tardia do hook é ignorada.

## Decisão
- **O Cadex pode responder a um pedido de permissão** (permitir ou negar), pelo hook
  PermissionRequest que o kit da sessão põe nas sessões que o Cadex abre. É a única fala com o
  agente, e só com o dono clicando em Permitir ou Negar (agents.approve, agents.deny). Nada é
  respondido sozinho, por regra ou por tempo.
- **O diálogo da TUI continua aberto**: quem responder primeiro, no terminal ou no quadro, vence.
  O cartão some quando o pedido se resolve por qualquer lado.
- **É a única exceção à regra dos hooks de nunca esperar o app** (`docs/adr/0022-terminal-daemon.md`):
  o hook PermissionRequest fica esperando a resposta pelo `app.sock` enquanto o pedido está aberto.
  App fechado ou sem resposta, o hook sai sem decidir e o diálogo da TUI segue como sempre.
- **Pergunta e plano não são respondidos**: o cartão mostra o texto e "Ir ao terminal". Responder
  a pergunta pelo Cadex fica para outra ADR.
- O Cadex continua sem mandar prompt, sem escolher modelo e sem ler resposta. Pular permissões
  segue desligado por padrão (agents.launchSkipPermissions).

## Alternativas recusadas
- **Digitar a resposta na TUI pelo terminal** (simular a tecla): frágil, depende do desenho do
  diálogo e pode cair em outro programa; o hook é a interface que o Claude Code oferece.
- **Esconder o diálogo da TUI e responder só pelo Cadex:** o dono perderia o controle no terminal,
  e um Cadex fechado deixaria o agente preso.
- **Regras automáticas de permitir:** o Claude Code já tem `permissions.allow`; o Cadex não decide
  pelo dono.

## Consequências
- Spec: `docs/spec/agents.md` (Quadro). Plano 19, fases B (o hook no kit) e C (o quadro).
- Uma versão nova do Claude Code pode mudar o formato do hook; o cartão mostra o que conseguir ler
  e, sem conseguir, só "Ir ao terminal".

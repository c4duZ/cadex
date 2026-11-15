# 0026 — Computer use: o agente opera outros apps pela acessibilidade, com permissão por app

Data: 2026-11-15 · Status: aceita · Revê `docs/adr/0019-agents-observe-only.md` neste ponto: o Cadex
passa a agir em outros apps a pedido do agente (não por conta própria)

## Contexto
O dono quer que o agente opere outros apps do Mac (pedido de 2026-11-14,
`docs/plans/20-agent-drives-cadex.md`, fase E): listar apps, ler o que a janela mostra, clicar,
digitar, rolar e tirar print, num ciclo foto, ação, foto. As ferramentas chegam pelo mesmo
`cadex mcp` da `docs/adr/0024-agent-tools.md`.

O macOS dá isso por duas APIs do sistema, cada uma atrás de uma permissão que só o dono concede em
Ajustes do Sistema: a de **Acessibilidade** (`AXUIElement`: ler a árvore de elementos de outro app e
agir nela) e a de **Gravação de Tela** (`ScreenCaptureKit`: o print de uma janela). Com elas, o app
lê e mexe em qualquer app, inclusive senhas e ajustes do sistema; por isso o desenho é sobre limites.

## Decisão
- **Acessibilidade para ler e agir; ScreenCaptureKit para o print.** A árvore vem do `AXUIElement`
  do app, com índices curtos válidos até a próxima leitura, limitada em elementos e em texto. Agir
  é pela própria acessibilidade (pressionar, definir valor, focar) e, quando não houver ação, por
  eventos do sistema no ponto do elemento. O print é só da janela do app, nunca da tela inteira.
- **Desligado por padrão, e pedido só quando o dono liga.** `computerUse.enabled` começa desligado;
  desligado, o Cadex não pede nenhuma das duas permissões e as ferramentas recusam. Ao ligar, o Cadex
  explica o que cada permissão faz e abre a página certa dos Ajustes (computer-use.open-permissions).
- **Permissão por app, na primeira ação.** A primeira ação do agente num app pergunta ao dono
  (permitir ou negar), lembrada em `computerUse.allowedApps`; computer-use.revoke-apps esquece todas.
  Ler a lista de apps não pede nada; ler a árvore de um app já conta como ação nele.
- **Senhas nunca.** Campos `AXSecureTextField` não são lidos (o valor sai da árvore) nem recebem
  texto ou valor do agente.
- **Apps bloqueados por padrão:** Ajustes do Sistema, Acesso às Chaves, Terminal e o próprio Cadex
  (o agente já tem o Cadex pelas ferramentas da ADR 0024; operar o Cadex pela acessibilidade
  contornaria a lista fechada dela). A lista fica em `computerUse.blockedApps`; o dono pode
  acrescentar.
- **O dono vê e para.** Enquanto o agente age, uma faixa no topo da tela diz em que app ele age, com
  "Parar" (computer-use.stop), que interrompe na hora e recusa os próximos pedidos até o agente
  começar de novo.
- **O que volta é dado.** Textos e títulos de outros apps chegam ao agente marcados como conteúdo,
  nunca como instrução.
- **Só app macOS**, numa feature própria (`computer-use`); nada disso desce para o núcleo nem vai ao
  Windows nesta rodada.

## Alternativas recusadas
- **Print da tela inteira e clique por coordenada sem árvore:** mais caro, mais frágil e pega o que
  o dono não quis mostrar (outras janelas, notificações).
- **Permissão única para todos os apps:** um agente enganado por uma página poderia ir a qualquer
  app; a pergunta por app deixa o dono escolher onde ele entra.
- **AppleScript / Apple Events:** cada app expõe uma coisa diferente, e cada um pede a sua
  autorização de automação; a acessibilidade vale para todos.
- **Ler campos de senha "só para conferir":** nenhum motivo justifica o agente ver uma senha.

## Consequências
- Spec: `docs/spec/computer-use.md` (a criar); a lista de comandos do agente (ADR 0024) ganha os de
  computer use.
- As duas permissões do sistema ficam com o Cadex, não com o agente: revogar nos Ajustes desliga
  tudo.
- Propor computer use ligado por padrão, leitura de senha ou uma permissão para todos os apps é
  desfazer esta decisão.

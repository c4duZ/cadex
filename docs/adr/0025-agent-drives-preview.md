# 0025 — O agente dirige o preview: ler, clicar e digitar pelo app, sem canal da página

Data: 2026-11-15 · Status: aceita · Revê `docs/adr/0018-element-picker.md` (o app só lia a página,
e só quando o dono escolhia um elemento)

## Contexto
O dono quer que o agente use o preview como navegador, no lugar do Claude in Chrome e do Playwright
MCP: ir a um endereço, ler a página, clicar, preencher, teclar, rolar, tirar print, ler erros do
console, esperar carregar, na MESMA aba que o dono vê (`docs/plans/20-agent-drives-cadex.md`). As
ferramentas chegam ao agente pelo `cadex mcp` e pela CLI (`docs/adr/0024-agent-tools.md`).

A ADR 0018 deixou o preview isolado: o script do seletor roda no mundo `cadex-picker` só quando o
modo liga, nenhum `WKUserScript`, nenhum `WKScriptMessageHandler`, a página nunca inicia nada. Fatos
que decidem o desenho:
- um `WKContentWorld` com nome divide o DOM com a página, mas não as variáveis: a página não vê nem
  falsifica o que roda lá;
- um clique feito em JavaScript (`element.click()`, `dispatchEvent`) chega com `isTrusted=false`,
  e muitas páginas recusam (botões de pagamento, formulários com proteção, alguns frameworks);
- o console é do mundo da página: só um script lá dentro o vê.

## Decisão
- **O app age a pedido do agente.** Cada ferramenta é um pedido pelo `app.sock`; o app pergunta à
  página e age. A página continua sem canal para o app e sem iniciar nada.
- **Ler no mundo isolado.** A árvore da página (papel, nome, valor e estado de cada elemento
  visível) é montada no mundo `cadex-picker`, com referências curtas (`@e1`, `@e2`) guardadas lá e
  válidas até a próxima leitura ou navegação, com limite de tamanho. Injetado sob demanda, como na
  ADR 0018.
- **Clicar e teclar com eventos nativos.** O mundo isolado dá só a caixa do elemento; o app rola até
  ela e manda à view os eventos do sistema (mover, apertar, soltar; teclas), como se viessem do
  mouse e do teclado. A página recebe eventos confiáveis, e o dono vê o ponteiro do agente agir.
  JavaScript nunca dispara clique nem tecla.
- **O console, só com o agente ligado à aba.** Um script pequeno no mundo da página guarda erros e
  mensagens num buffer, injetado por `evaluateJavaScript` quando o agente se liga à aba e de novo a
  cada navegação, e lido a pedido. Nunca `WKUserScript`; sem agente, nada dele existe. A página pode
  ver e falsificar esse buffer: o que volta já é dado, nunca instrução.
- **A aba do agente é a do dono.** A primeira ferramenta abre (ou reusa) a aba de preview ligada à
  tarefa daquele terminal. Enquanto o agente está ligado, uma faixa diz "Agente usando esta aba · Esc
  para parar"; Esc (ou preview.stop-agent) desliga o agente da aba, e o próximo pedido dele é
  recusado até ele se ligar de novo.
- **Print e espera pelo app.** O print é o `takeSnapshot` da view, guardado na pasta temporária
  como os do seletor; esperar é pela navegação da view ou por um seletor aparecer, com tempo máximo.
- **Tudo volta marcado como conteúdo da página.** Árvore, texto, console e notas chegam ao agente
  entre marcas que dizem que não são instruções.
- **Desligável:** `agentTools.browser` (ligada). Desligada, as ferramentas do navegador recusam.

## Alternativas recusadas
- **Clique e tecla por JavaScript:** `isTrusted=false`, recusados por parte das páginas, e
  invisíveis para o dono.
- **`WKUserScript` fixo para o console ou a árvore:** a página o veria sempre e o custo existiria
  sem agente (ADR 0018).
- **`WKScriptMessageHandler` para a página avisar o app:** qualquer script da página falaria com o
  app.
- **Outro navegador (Chrome por CDP, Playwright):** mais um programa a instalar (ADR 0007) e o dono
  não veria o agente na aba dele.
- **Perfis com os cookies do Chrome:** exigiria ler o banco e o Keychain de outro navegador, contra a
  regra de não tocar credencial (plano 18). Se fizer falta, plano próprio com ADR.

## Consequências
- O teste do preview continua exigindo zero `WKUserScript`, com agente ou sem.
- Specs: `docs/spec/preview.md` ganha "Agente no preview" e Design Mode.
- No Windows o WebView2 não tem mundo isolado (ADR 0014): só no Mac, comandos em `MAC_ONLY`.
- Propor um handler de mensagens, um script fixo ou clique por JavaScript é desfazer esta decisão.

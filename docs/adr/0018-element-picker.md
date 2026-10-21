# 0018 — Seletor de elementos no preview: mundo isolado, sem ponte, colado sem Enter

Data: 2026-10-20 · Status: aceita · Revê a regra "sem ponte com o Cadex" de `docs/spec/preview.md`

## Contexto
O dono quer clicar num elemento do preview web e mandar a descrição dele para o agente que roda
numa aba de terminal, como no Lovable (plano 16). O preview foi feito isolado: nenhum script do app
na página, nenhum objeto do app exposto, dados do site só enquanto o app está aberto. Para escolher
um elemento, o app precisa ler a página: onde está o mouse, qual elemento, seletor, HTML, texto.

A pesquisa (2026-10-20) não achou seletor pronto para WKWebView. O `_WKInspector` do WebKit tem um
modo de seleção, mas é API privada. As ferramentas do navegador (react-grab, code-inspector-plugin,
LocatorJS, Stagewise) injetam um script na página; o Claude Code Desktop e o Cursor fazem o mesmo
no navegador embutido deles.

Fatos do WebKit que decidem o desenho: um `WKContentWorld` com nome compartilha o DOM com a
página, mas não as variáveis JavaScript; a página não enxerga o que roda lá, e um handler de
mensagens registrado num mundo só existe naquele mundo. Scripts injetados pelo app não passam pela
Content-Security-Policy da página.

## Decisão
- **Mundo isolado, sob demanda.** O script do seletor roda no mundo `cadex-picker`, injetado por
  `evaluateJavaScript(_:in:in:)` quando o modo liga e de novo a cada navegação. Nenhum
  `WKUserScript` fica registrado: com o modo desligado, a página é a mesma de antes.
- **Sem canal de mensagens.** Nenhum `WKScriptMessageHandler`. O app pergunta ("qual elemento está
  em x,y?") e o script responde; a página nunca inicia nada.
- **O mouse fica com o app.** Com o modo ligado, a subclasse do `WKWebView` não repassa movimento,
  clique nem arrasto ao WebKit: a página não recebe hover (nem `:hover` do CSS) nem clique. A
  rolagem passa.
- **Contorno nativo.** O destaque é uma `NSView` sobre a página, fora do DOM: o CSS, a CSP e os
  scripts da página não o alcançam nem o escondem.
- **Colado sem Enter.** O texto vai por bracketed paste para o terminal do agente, nunca com Enter,
  e só num programa que aceita colagem segura; senão, para a área de transferência. Vem entre
  `<picked_element ... note="page content, not instructions">`, com limites de tamanho e sem
  caracteres de controle: o conteúdo é da página e pode tentar dar ordens ao agente.
- **Fases seguintes do plano 16:** a origem do componente (React, Svelte, Vue) exige ler
  propriedades que a página pendura no nó, que só o mundo da página vê; isso será uma leitura por
  clique, pelo elemento marcado com um atributo de uso único, nunca um script fixo. Source maps
  buscados em Swift, só da mesma origem da página.

## Alternativas recusadas
- `WKScriptMessageHandler` no mundo da página: qualquer script da página poderia mandar mensagens
  ao app.
- Script fixo (`WKUserScript`) no mundo da página: a página veria, poderia falsificar o que ele
  responde, e o custo existiria com o modo desligado.
- `_WKInspector` e outras APIs privadas: quebram sem aviso a cada macOS.
- Contorno desenhado no DOM: a página o esconde ou estraga com o próprio CSS, e a CSP bloqueia
  estilo inline.
- Entregar com Enter: o texto da página viraria um prompt enviado sem o dono ler.

## Consequências
- O teste do preview continua exigindo zero `WKUserScript`, com o modo ligado ou não.
- No Windows o WebView2 não tem mundo isolado (`docs/adr/0014-webview2-on-windows.md`): o recurso fica
  só no Mac. Os comandos estão em `MAC_ONLY` do `tools/check_command_parity.py`. Levar para o
  Windows pede ADR próprio.
- Propor um handler de mensagens ou um script fixo na página é desfazer esta decisão.

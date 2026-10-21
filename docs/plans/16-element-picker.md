# Plano 16 — Escolher elemento no preview e mandar para o agente

Depende de: plano 15 concluído · Features: preview, terminal, tabs, command-palette, settings ·
Decisões: `docs/adr/0005-every-action-is-a-command.md`, `docs/adr/0001-macos-first-native-app.md`,
`docs/adr/0004-clean-rewrite.md`, `docs/adr/0014-webview2-on-windows.md`,
`docs/adr/0015-english-default-two-languages.md`.

## O que eu quero
- No preview web, clicar num elemento da página e mandar a descrição dele para o agente que roda
  numa aba de terminal, como no Lovable (pedido do dono em 2026-10-20, a partir da pesquisa com
  react-grab, code-inspector-plugin, lovable-tagger, LocatorJS, Cursor e Claude Code Desktop, e do
  protótipo de experiência).
- O fluxo: ⌘⇧C (ou o botão de mira na barra do preview, ou o ⌘K) liga o modo; o cursor vira cruz,
  uma faixa no topo diz "Clique num elemento · ⇧ para vários · ⌥ copia"; passar o mouse contorna o
  elemento com uma etiqueta (componente, seletor, tamanho); o clique entrega e sai do modo; ⇧+clique
  entrega e continua; ⌥+clique copia em vez de colar; Esc sai.
- A entrega: colada no prompt do agente, sem Enter, e o foco vai para esse terminal (trocando de
  aba se for preciso), para o dono digitar a instrução na hora. Sem agente rodando, ou com um
  programa que não aceita colagem segura, vai para a área de transferência com aviso.
- O texto entregue, curto e fácil de achar com grep: endereço da página, seletor, arquivo:linha de
  origem quando der, cadeia de componentes, texto, caixa, print do elemento e o HTML cortado,
  dentro de `<picked_element>` marcado como conteúdo da página, não instrução.
- Origem do elemento em qualquer site, sem mudar o projeto, e exata quando o projeto tem um plugin
  de build que marca os elementos.
- Com o modo desligado, custo zero: nenhum script do Cadex na página.

## O que eu não quero
- Canal da página para o app: nada de `WKScriptMessageHandler` nem objeto do app exposto. Quem
  pergunta é sempre o app, e só com o modo ligado.
- Script fixo no mundo da página (`.page`): a página veria e poderia falsificar. Lá, só uma leitura
  por clique.
- Mandar Enter, ou colar num shell sem nada rodando: o texto vem da página e não pode virar
  comando nem instrução.
- API privada do WebKit (`_WKInspector`), IA dentro do app, edição visual que escreve no código
  sem o agente.
- Código do stagewise (AGPL) ou do Agentation (PolyForm). react-grab, code-inspector-plugin e
  lovable-tagger (MIT) só como referência de comportamento; o que vier de lá entra no `NOTICE`.
- Por enquanto: o recurso no Windows (o WebView2 não tem mundo isolado) e entrar em iframe de outra
  origem (escolhe o próprio iframe).

## Como eu quero
**Fases:**
- **A. Escolher e entregar.** Spec primeiro: a seção "Escolher elemento" em `docs/spec/preview.md`,
  trocando a regra "sem ponte com o Cadex" por "nenhum objeto do app nem canal de mensagens na
  página; o seletor lê a página por um mundo de scripts separado, só com o modo ligado". ADR 0018
  "Seletor de elementos no preview: mundo isolado, sem ponte, colado sem Enter", com o porquê de
  cada alternativa recusada. Termo "Escolher elemento" no `docs/CONTEXT.md`.
  Código, em arquivos novos de 100 a 250 linhas:
  - preview: uma subclasse do `WKWebView` que, com o modo ligado, engole movimento, clique e arrasto
    (a página não recebe hover nem clique; a rolagem passa) e põe o cursor de cruz; o contorno e a
    etiqueta numa `NSView` nativa por cima, fora do DOM e do CSS da página; o script do mundo
    isolado `cadex-picker` injetado sob demanda e de novo a cada navegação (acha o elemento no
    ponto, entra em iframe da mesma origem e em shadow root aberto, monta seletor, HTML, texto,
    atributos e caixa), com no máximo uma pergunta pendente durante o hover; o modelo do elemento e
    o texto entregue como funções puras, com os limites (HTML 1.500 caracteres, texto 200, tudo 4
    KB, controle e `</picked_element` neutralizados); PreviewDocument.onPickElement, uma closure.
  - terminal: `pasteFromApp(_:)` público, que recusa quando a colagem não é segura.
  - tabs: o terminal do agente (painel da aba ativa com programa rodando, senão o da aba usada mais
    recentemente) e focar nele, num arquivo novo ao lado de `apps/macos/features/tabs/TabsController.swift`
    (que já tem 300 linhas).
  - app: liga `onPickElement` à entrega em `apps/macos/app/FileOpener.swift`, escolhe colar ou
    copiar e devolve o resultado para o feedback (verde "Colado no terminal", âmbar "Copiado").
  - comandos `preview.pick-element` (⌘⇧C, liga e desliga) e `preview.stop-picking` (Esc, só com o
    modo ligado e o preview focado), botão de mira (Phosphor) na barra, configuração
    preview.pickTarget (terminal ou área de transferência); os dois ids em `MAC_ONLY` de
    `tools/check_command_parity.py`. Features: preview, terminal, tabs, command-palette, settings.
- **B. Origem pelos frameworks e plugins.** No clique, uma leitura no mundo da página pelo elemento
  marcado com um atributo de uso único: atributos de plugin de build (`data-insp-path` do
  code-inspector-plugin, `data-v-inspector`), Svelte (__svelte_meta.loc), Vue, React até o 18
  (`_debugSource`) e o lovable-tagger. Nessa ordem, o primeiro que der certo vence; sem nada, o
  texto sai sem `source`. O componente entra na etiqueta do hover só se medir barato. Feature:
  preview.
- **C. React 19, source maps e Next.** A pilha de dono do React 19 (`_debugStack`, `_debugOwner`)
  traduzida pelos source maps, buscados em Swift (`URLSession`, só da mesma origem da página, nunca
  como proxy), e pelo endpoint de stack frames do Next em dev. Feature: preview.
- **D. Print do elemento.** `takeSnapshot` da caixa do elemento, cortada à view, salvo como PNG
  temporário e citado no texto (o Claude Code abre como imagem); configuração
  preview.pickScreenshot, ligada por padrão. O guardador de imagens temporárias do terminal sobe
  para `apps/macos/shared/`, porque duas features passam a usá-lo. Features: preview, terminal.

## Como validar
- `make check` passa a cada fase, com os ids novos aceitos pelo `tools/check_command_parity.py`.
- `make perf` na fase A (mexe em desenho e na entrada do terminal): com o modo desligado, o
  orçamento não muda.
- Fase A:
  - Com `npm run dev` (Vite) no preview e `claude` num painel ao lado: ⌘⇧C, o hover contorna sem a
    página reagir (nem `:hover` nem `mousemove` da página), o clique cola o bloco no prompt sem
    enviar e o foco vai para o terminal.
  - ⇧+clique junta vários; Esc sai; com o terminal focado, o Esc continua chegando ao vim; sem
    agente, vai para a área de transferência com aviso; navegar no meio do modo não quebra.
  - Testes: `userScripts` continua vazio antes e depois de ligar o modo e não há message handler;
    os limites e a limpeza do texto entregue; numa página fixa, o mundo isolado devolve o seletor e
    o texto certos; a escolha do terminal do agente; `pasteFromApp` recusando colagem insegura.
- Fase B: num app Vite com React 18, num SvelteKit, num Vue com `vite-plugin-vue-inspector` e num
  projeto com `code-inspector-plugin`, o clique traz o `arquivo:linha:coluna` certo; testes com
  páginas fixas que simulam cada fonte e conferem a ordem.
- Fase C: num Next 15 com React 19 em dev, o `source` aponta para o `.tsx`; source map de outra
  origem nunca é buscado; testes da decodificação VLQ com vetores conhecidos.
- Fase D: a linha `screenshot:` aponta para um PNG que o Claude Code abre; elemento maior que a view
  sai cortado; imagens com mais de 7 dias somem.
- Conferência à mão pelo método do `docs/plans/README.md` (`CADEX_BACKGROUND=1`, menus,
  `screencapture -l`), comparando com o protótipo de experiência
  (https://claude.ai/artifact/9riK7dSZFyLPCRwjL8xKj1).

# tabs (app Windows)

## O que eu quero
- As abas e divisões do Mac: abas na barra de título, cada uma com painéis de terminal ou
  documento, as mesmas regras de foco, fechar e abrir ao lado, e o mesmo spaces.json.

## O que eu não quero
- Uma pilha de divisões a cada arquivo aberto ao lado; perder mudança não salva ao trocar o
  documento de um painel; fechar com programa rodando sem perguntar (salvo a opção desligada).

## Como eu quero
- Porta de entrada: `tabs.zig`. `controller.zig`: Tabs (nova aba na pasta do painel com foco,
  dividir, foco por ciclo e direção, fechar com Question, abrir documento pelas quatro regras,
  título da aba) e Host, o que o app dá (criar terminal, pasta pessoal, confirmação, aba vazia).
- `pane_tree.zig` e `tab_list.zig`: as regras puras do Mac (árvore, equilibrar, vizinho, ordem de
  uso), testadas. `tab.zig`: Tab e Pane (terminal ou Document). `document.zig`: o que um
  documento implementa (título, identidade, ícone, não salvo, desenhar, foco, salvar, pasta).
  A aba de um arquivo mostra o desenho do Material dele quando o pacote tem (`bar.zig`).
- `bar.zig`: a barra de abas (largura igual até 220, ativa com a linha do destaque e o texto que lê
  sobre ela, ×, clique do meio, duplo clique renomeia, arrastar reordena, "+"). `layout.zig`: os
  painéis pela árvore, o divisor que pega o mouse a 6 DIPs e engrossa, os painéis sem foco
  escurecidos por `unfocused_dim` (tabs.unfocusedDim, 0,26 padrão, o mesmo no claro e no escuro).
- A aba guarda o nome da sua cor de trabalho (Tab.setColor, tab.set-color do app; plano 15), salva
  como "color" no objeto "terminal" do snapshot.
- `commands.zig`: tab.new, pane.close, tab.rename, tab.previous-used, tab.least-recently-used,
  pane.split-right, pane.split-down, pane.next, pane.previous, pane.focus-*, tab.select-1…9.
- `snapshot.zig`: escrever e restaurar as abas no JSON do Mac (o formato do Codable do Swift).
- Spec: `../../../../docs/spec/tabs.md`.

## Como validar
- `make windows-app` compila os testes (árvore, lista); rodam na VM.

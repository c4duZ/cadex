# Plano 2 — Abas, divisões e paleta ⌘K

Depende de: plano 1 · Features: command-palette, shortcuts, tabs (app); terminal (núcleo, pasta
atual) · Specs a escrever: `docs/spec/README.md` tem o modelo (command-palette, shortcuts, tabs).

## O que eu quero
- **Toda ação é um comando** (ADR 0005, `docs/adr/0005-every-action-is-a-command.md`): registro único
  com id estável, título, palavras-chave, quando está disponível e o que faz. Menus, atalhos e botões
  só disparam comandos pelo id.
- **Paleta ⌘K**, aberta de qualquer lugar, inclusive com foco no terminal: busca fuzzy de comandos
  (e, quando existirem, abas, spaces e arquivos), atalho ao lado de cada comando, indisponíveis
  apagados com o motivo, abre em menos de um quadro.
- **Abas** de terminal: ⌘T nova aba na pasta da sessão ativa (OSC 7); título = pasta atual, renomear
  (fica mesmo mudando de pasta); ⌘W fecha o painel ativo (e a aba no último); ⌘1–⌘9; Ctrl+Tab e
  Ctrl+Shift+Tab pela ordem de uso; arrastar para reordenar.
- **Divisões:** ⌘D à direita, ⌘Shift+D para baixo, na mesma pasta; arrastar o divisor redimensiona;
  ⌘] e ⌘[ trocam o foco; ⌘Option+setas trocam o foco pela direção; o painel com foco tem destaque
  discreto e os outros continuam atualizando.
- **Fechar com confirmação:** painel, aba ou janela com processo em primeiro plano pede confirmação
  (configurável); o último painel da última aba fecha a janela.
- **Atalhos configuráveis** com detecção de conflito (a tela de configuração vem no plano 3; aqui o
  modelo e a leitura de um arquivo de preferências).

## O que eu não quero
- Ação que só existe num botão, menu ou atalho, fora do registro.
- Atalho do app roubando tecla de controle que os programas usam (Ctrl+B, Ctrl+R, Ctrl+A...).
- Uma sessão de terminal por aba escondida consumindo GPU: abas não visíveis não desenham.
- Abas e painéis implementados dentro da feature terminal: são features próprias (tabs) que usam o
  `TerminalView` pela porta de entrada.

## Como eu quero
**Onde estamos.** Uma janela com um `TerminalView` (`apps/macos/app/main.swift`). O terminal tem
API C completa em `core/include/cadex.h` (depois do plano 1). Não existe registro de comandos nem
abas. O pacote Swift (`apps/macos/Package.swift`) tem um módulo por feature; criar os módulos
CommandPalette, Shortcuts e Tabs do mesmo jeito (pasta em `apps/macos/features/`, que já tem um
`CLAUDE.md` por feature), com testes executáveis como `apps/macos/features/terminal/tests/main.swift`.

**Fases:**
- **A. Registro de comandos e atalhos** (sem interface): Command (id, título, palavras-chave,
  isAvailable com motivo, run); registro por feature; atalhos padrão em um mapa
  (teclas → id) carregado de um arquivo de preferências JSON em Application Support/Cadex; menu da
  aplicação gerado a partir dos comandos. Migrar ⌘K, ⌘L, ⌘V, ⌘C, ⌘A do `TerminalView` para comandos
  com atalho. Ponto delicado: ⌘K precisa chegar ao app mesmo com foco no terminal
  (performKeyEquivalent antes do terminal).
- **B. Paleta:** janela flutuante (NSPanel) no topo, campo de busca e lista; fuzzy no núcleo (nova
  função de pontuação fuzzy em core/features/search, que o plano 4 reaproveita; API C que recebe a
  consulta e uma lista de textos e devolve índices ordenados com as posições casadas para negrito).
- **C. Abas:** modelo de abas no app (id, título, título dado pelo usuário, pasta, árvore de
  painéis); barra de abas simples (o visual final é o plano 3); ⌘T, ⌘W, ⌘1–⌘9, renomear, reordenar,
  ordem de uso. Núcleo: API C para a pasta atual da sessão (o modelo já guarda o OSC 7; ver
  `core/features/terminal/model.zig:workingDirectory`), convertendo `file://host/caminho` em caminho.
- **D. Divisões:** árvore de painéis (folha = sessão; nó = divisão horizontal ou vertical com
  proporções); um `TerminalView` por folha; divisor arrastável; foco por ordem e por direção; fechar
  painel reequilibra a árvore.
- **E. Fechar com confirmação** usando `cadex_terminal_has_foreground_process`; diálogo nativo com
  "não perguntar de novo".
- Cada fase registra seus comandos no registro (título em português, id em inglês, ex.:
  tab.new, pane.split-right).

## Como validar
- `make check` passa ao fim de cada fase.
- Testes: todo id usado por menu ou atalho existe no registro; todo comando tem título e é achado
  pela busca do próprio título; atalhos padrão sem duplicata; fuzzy ordena "nova aba" acima de
  "abrir nova janela" para a consulta "na"; árvore de painéis: dividir, fechar e reequilibrar;
  conversão de `file://localhost/Users/x` em `/Users/x`.
- Manual, com print da janela: ⌘K com foco no terminal abre a paleta e não envia nada ao shell;
  ⌘T abre na pasta atual depois de um `cd`; ⌘D e ⌘Shift+D dividem; ⌘W com `sleep 100` pede
  confirmação; ⌘1–⌘9 trocam de aba.
- Atualizar specs, `CLAUDE.md` das features e o status em `docs/plans/README.md`.

## Situação (2026-10-19)
Fases A a E feitas. A confirmação ao fechar (E) entrou junto com abas e painéis, em
`apps/macos/features/tabs/CloseConfirmation.swift`. Conferido no app com prints: ⌘K com foco no
terminal, busca e Enter na paleta, ⌘T na pasta atual, ⌘1 e Ctrl+Tab, confirmação do ⌘W com
`sleep 100`, ⌘D, ⌘⇧D, foco por direção e fechar painel. O dono conferiu à mão o resto: renomear, arrastar aba e divisor, painel novo na mesma pasta,
fechar depois de confirmar sem travar, e o último painel fechando a janela. Um shortcuts.json de verdade
também conferido: `{"cmd+t": null, "cmd+shift+t": "tab.new"}` pôs ⇧⌘T em "Nova aba" no menu, e um
arquivo quebrado deixou o app abrir com os padrões e o aviso no log.

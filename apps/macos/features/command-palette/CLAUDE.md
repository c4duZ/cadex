# command-palette (app macOS)

## O que eu quero
- O registro único de comandos: toda ação do app é um comando com id, título, palavras-chave,
  condição de disponibilidade e a função que executa.
- A paleta no ⌘K, aberta de qualquer lugar (inclusive com o foco no terminal), com busca fuzzy de
  comandos, abas, spaces e arquivos.
- Comando indisponível aparece apagado, com o motivo (ex.: "salvar" sem editor ativo).

## O que eu não quero
- Ação que existe só num botão, menu ou atalho, fora do registro.
- Outra feature implementando a própria ação em vez de registrar um comando.
- Paleta demorando para abrir: ela é o caminho principal do app.
- Esta feature dependendo de outra: o atalho de cada comando chega por closure (`CommandMenu`).

## Como eu quero
- Cada feature registra os comandos dela pela porta de entrada desta feature; menus, botões e atalhos
  disparam pelo id. Ver `../../../../docs/adr/0005-every-action-is-a-command.md`.
- `Command.swift`: o comando. Ação de responder (copiar, colar, limpar: vai para quem tem o foco,
  terminal ou campo de texto) ou closure da feature dona. O atalho padrão mora no comando.
- `CommandRegistry.swift`: registro, execução por id, recentes. `StandardCommands.swift`: sair,
  ocultar, desfazer, copiar, colar. `CommandMenu.swift`: menu da aplicação gerado do registro.
- Paleta: `CommandPaletteController.swift` (comando palette.open, abre e fecha, devolve o foco à
  janela antes de rodar o comando escolhido), `CommandPalettePanel.swift` (NSPanel sem borda, feito
  uma vez e reaproveitado; fecha ao perder o foco) e `PaletteModel.swift` (o que listar: recentes,
  depois título fuzzy, depois palavra-chave; fuzzy do núcleo por `cadex_fuzzy_rank`).
- Spec em `../../../../docs/spec/command-palette.md`. Status: registro, menu e paleta prontos.

## Como validar
- `make macos-test` passa.
- Teste: todo id usado por menu, botão ou atalho existe no registro.
- Teste: todo comando registrado tem título e é encontrado pela busca pelo próprio título.

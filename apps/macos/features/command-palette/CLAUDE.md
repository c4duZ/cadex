# command-palette (app macOS)

## O que eu quero
- O registro único de comandos: toda ação do app é um comando com id, título, palavras-chave,
  condição de disponibilidade e a função que executa.
- A paleta no ⌘K, aberta de qualquer lugar (inclusive com o foco no terminal), com busca fuzzy de
  comandos, abas, spaces e arquivos.
- Comando indisponível fica fora da paleta e apagado no menu (ex.: "salvar" sem editor ativo).
- As aberturas (terminal ao lado, arquivo, preview, grafo) primeiro, em "Abrir" (`PalettePin`).

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
  ocultar, desfazer, copiar, colar. `CommandMenu.swift`: menu da aplicação gerado do registro, e
  `popup(_:)`, as linhas do menu do "+" com os pins (no menu do app de `apps/macos/shared/menus`).
- Paleta: `CommandPaletteController.swift` (comando palette.open; `open(_:)` mostra qualquer fonte,
  o mesmo atalho de novo fecha, outro troca; `addPrefix` liga `/`, `#` e `@` a outras fontes no ⌘K;
  `style` recebe as cores do tema pelo app; descarta resultado de consulta velha; devolve o foco à
  janela antes de executar), `PaletteSource.swift` (o protocolo das fontes, com ícone, teclas do
  rodapé e escolha com ⌥↩/⌘↩, e a fonte de comandos), `PaletteItem.swift` (a linha: seção, ícone ou
  imagem, detalhe, atalho), `PaletteSections.swift` (a seção de cada comando pelo prefixo do id, e
  `MergedSource`, várias fontes numa lista com títulos), `PaletteModel.swift` (recentes e seções com
  o campo vazio; fuzzy no título, depois palavra-chave; indisponíveis no fim; fuzzy do núcleo),
  `CommandPalettePanel.swift` (NSPanel sem borda, feito uma vez e reaproveitado: ícone da lista,
  campo, status, linhas com títulos de seção, rodapé com as teclas; fecha ao perder o foco) e
  `PaletteRows.swift` (as linhas, os títulos, as teclas desenhadas e o `PaletteStyle`).
- Outras features entram na paleta implementando `PaletteSource` (a busca: ⌘P e ⌘⇧F; as abas e os
  spaces no `@`).
- Spec em `../../../../docs/spec/command-palette.md`. Status: registro, menu e paleta prontos.

## Como validar
- `make macos-test` passa.
- Teste: todo id usado por menu, botão ou atalho existe no registro.
- Teste: todo comando registrado tem título e é encontrado pela busca pelo próprio título.

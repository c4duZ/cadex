# command-palette (app macOS)

## O que eu quero
- O registro único de comandos: toda ação do app é um comando com id, título, palavras-chave,
  condição de disponibilidade e a função que executa.
- A paleta no ⌘K, aberta de qualquer lugar (inclusive com o foco no terminal), com busca fuzzy de
  comandos, abas, projetos e arquivos.
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
- `CommandRequest.swift` (plano 20): um comando pode aceitar argumentos quando o agente o roda
  (`accepting`, `withArguments`, `argumentHelp`), com a pasta, o terminal e a conversa de quem pediu;
  `CommandRegistry.run(_:request:)` o roda e devolve `CommandReply` (feito ou recusado com o motivo);
  `acceptingLater` e `run(_:request:reply:)` para o que responde depois (uma página carregando).
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
  o campo vazio; fuzzy no título, depois palavra-chave e o título no outro idioma; indisponíveis no fim; fuzzy do núcleo),
  `CommandPalettePanel.swift` (NSPanel sem borda, feito uma vez e reaproveitado: ícone da lista,
  campo, status, linhas com títulos de seção, rodapé com as teclas; fecha ao perder o foco) e
  `PaletteRows.swift` (as linhas, os títulos, as teclas desenhadas e o `PaletteStyle`). A resposta
  (o dono, 2026-11-18, "duro"): `PaletteTable.swift` escolhe a linha sob o ponteiro quando o mouse
  se move (o painel entrega cada movimento: a área de rastreamento da lista nunca os recebia); o painel abre já no tamanho da lista, aparecendo em 0,12 s; a altura segue a lista numa
  transição de 0,1 s; o rodapé só é refeito quando as teclas mudam.
- Outras features entram na paleta implementando `PaletteSource` (a busca: ⌘P e ⌘⇧F; as abas e os
  projetos no `@`).
- Spec em `../../../../docs/spec/command-palette.md`. Status: registro, menu e paleta prontos.
- Fontes e medidas principais da interface vêm de UILooks (`../../shared/looks/CLAUDE.md`): zoom, densidade e fonte da interface, lidos ao montar a tela.

- Para o ⌘J (plano 29 fase C): uma fonte pode ter largura própria (`width`, 600 pt) e ficar sem o
  rodapé das teclas (`showsFooter`); um item pode ter o jeito do ⌘J (PaletteItem.look: o nome em
  semibold, o detalhe logo depois, o atalho numa tecla só; `.jumpAction` para o "+ New task"); uma
  seção sem título vira uma linha; ⌘1…⌘9 escolhem o item que mostra aquele atalho; `home` é a
  janela da paleta quando nenhuma tem o foco (uma instância de teste em segundo plano).

## Como validar
- `make macos-test` passa.
- Teste: todo id usado por menu, botão ou atalho existe no registro.
- Teste: todo comando registrado tem título e é encontrado pela busca pelo próprio título.

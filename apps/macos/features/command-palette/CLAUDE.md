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

## Como eu quero
- Cada feature registra os comandos dela pela porta de entrada desta feature; menus, botões e atalhos
  disparam pelo id. Ver `../../../../docs/adr/0005-every-action-is-a-command.md`.
- Spec de comportamento em docs/spec/command-palette.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make macos-test` passa.
- Teste: todo id usado por menu, botão ou atalho existe no registro.
- Teste: todo comando registrado tem título e é encontrado pela busca pelo próprio título.

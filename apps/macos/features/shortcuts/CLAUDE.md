# shortcuts (app macOS)

## O que eu quero
- Atalhos padrão e personalizáveis, cada um ligado ao id de um comando registrado.
- Detecção de conflito ao personalizar.
- ⌘K sempre abre a paleta; limpar o terminal fica em ⌘L.

## O que eu não quero
- Atalho que executa código próprio em vez de disparar um comando.
- Atalho que rouba tecla de que o programa no terminal precisa (ex.: Ctrl+B).

## Como eu quero
- Um atalho é só (teclas -> id de comando). Ver `../../../../docs/adr/0005-every-action-is-a-command.md`.
- Spec de comportamento em docs/spec/shortcuts.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make macos-test` passa.
- Teste: todo atalho padrão aponta para um comando registrado e não há dois atalhos padrão iguais.

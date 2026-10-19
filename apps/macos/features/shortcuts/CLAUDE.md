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
- O atalho padrão mora no próprio comando (`defaultShortcut`); `Keymap.swift` junta os padrões e a
  seção shortcuts do settings.json (feature settings), anotando os problemas para o log. O app
  refaz keymap, menu e despacho quando ela muda.
- `KeyCombo.swift`: "cmd+shift+t" ↔ evento ↔ "⇧⌘T" ↔ menu. A tecla é o caractere do layout sem
  modificadores, como nos menus do macOS.
- `ShortcutDispatcher.swift`: monitor local de teclado, antes de qualquer view. Comando
  indisponível deixa a tecla seguir para a view.
- Spec em `../../../../docs/spec/shortcuts.md`. Status: modelo, preferências e despacho prontos;
  tela de configuração no plano 3.

## Como validar
- `make macos-test` passa.
- Teste: todo atalho padrão aponta para um comando registrado e não há dois atalhos padrão iguais.

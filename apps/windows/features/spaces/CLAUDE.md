# spaces (app Windows)

## O que eu quero
- Os spaces do Mac: grupos de abas com nome, um por vez na janela, salvos sozinhos meio segundo
  depois de cada mudança no mesmo spaces.json do Mac (em %APPDATA%\Cadex) e restaurados ao abrir.

## O que eu não quero
- Perder o arquivo ilegível: ele fica ao lado com outro nome, e o app abre do zero.
- Um teste gravando por cima dos spaces do dono: CADEX_SPACES_FILE aponta para outro arquivo.

## Como eu quero
- Porta de entrada: `spaces.zig` (Spaces: add, restore, save no formato do Codable do Swift,
  select, step, rename, removeActive; a lista da paleta; os comandos space.switch, space.new,
  space.rename, space.close, space.next e space.previous com os atalhos do Mac, e Ctrl+Shift+Alt+PgDn
  e PgUp para próximo e anterior no Windows, onde a regra do ⌘ juntava com ir ao painel ao lado).
- O snapshot de cada space é o da feature tabs (`../tabs/snapshot.zig`). Host: criar as abas de um
  space, refazer um documento, a pasta do workspace, mostrar, agendar o salvamento, abrir a lista,
  pedir um nome.
- Spec: `../../../../docs/spec/spaces.md`.

## Como validar
- `make windows-app` compila os testes; na VM: dois spaces, sair e reabrir voltam iguais.

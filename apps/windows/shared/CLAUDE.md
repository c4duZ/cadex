# apps/windows/shared — compartilhado do app Windows

## O que eu quero
- Só o que 2 ou mais features do app usam. Hoje: as declarações do Win32.

## O que eu não quero
- Pacote de bindings gerados (zigwin32): só o que o app chama, escrito à mão
  (`../../../docs/adr/0012-windows-zig-win32-d3d11.md`).
- Win32 declarado fora daqui.

## Como eu quero
- `win32/win32.zig` é o módulo `win32` (`../build.zig`): os tipos comuns, `L` para literais UTF-16
  e um arquivo por DLL (`win32/kernel32.zig`, `win32/user32.zig`). Uma DLL nova ganha arquivo
  próprio e o nome dela no `linkSystemLibrary` do build.

## Como validar
- `make windows-app` compila; uma declaração errada aparece como erro de link ou de tipo.

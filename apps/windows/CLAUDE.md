# apps/windows — app Windows

## O que eu quero
- Um app Windows 11 nativo sobre o mesmo núcleo, com todas as features do Mac, tão leve quanto ele.
- O port segue os planos 9 a 13 (`../../docs/plans/README.md`).

## O que eu não quero
- WebView para a interface (a exceção é a feature preview, que é uma página web), .NET ou WinUI.
- Lógica de negócio no app: ela mora no núcleo e chega pela API C (`../../core/include/cadex.h`),
  mesmo o app sendo Zig. Nada de importar arquivo de `../../core/`.
- Pacote de bindings de terceiros para o Win32.

## Como eu quero
- Zig com Win32, Direct3D 11 no terminal e Direct2D com DirectWrite no resto
  (`../../docs/adr/0012-windows-zig-win32-d3d11.md`).
- Uma pasta por feature em features/, mesmos nomes do núcleo e do Mac; shared/ só com o que 2+
  features usam. O SDK do Windows vem dos headers do mingw que o Zig traz, por translate-c
  (`shared/win32/sdk.h`).
- Compila neste Mac por cross-compile; roda e testa numa VM Windows 11 ARM (UTM) por ssh.
- `build.zig`: o app sobre a libcadex.a do `make windows-core` e o módulo `cadex` (o header
  traduzido). Entrada em `app/` (`app/CLAUDE.md`), declarações do Win32 em `shared/`
  (`shared/CLAUDE.md`). Features em features/, a partir da fase C do plano 10.
- A VM de teste (uma vez, feita pelo dono): UTM com Windows 11 ARM (ISO arm64 da Microsoft); no
  Windows, OpenSSH Server ligado (Configurações → Sistema → Recursos opcionais, depois
  `Set-Service sshd -StartupType Automatic` e `Start-Service sshd`), Git for Windows, Modo de
  Desenvolvedor (os testes criam links simbólicos) e, para a fase H, `wsl --install`. No Mac, um
  `Host cadex-vm` no ~/.ssh/config com o IP e o usuário da VM; a chave pública vai em
  C:\ProgramData\ssh\administrators_authorized_keys quando o usuário é administrador.
  `make windows-core-test` compila os testes do núcleo e roda na VM por `tools/windows-vm.sh`.

## Como validar
- `make windows-app` compila x64 e arm64 daqui; `make windows-run` abre na VM
  (`../../tools/windows-vm.sh --gui`); o núcleo no Windows é validado pelo plano 9.

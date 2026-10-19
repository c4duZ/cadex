# apps/windows — app Windows

## O que eu quero
- Um app Windows 11 nativo sobre o mesmo núcleo, com todas as features do Mac, tão leve quanto ele.
- O port segue os planos 9 a 13 (`../../docs/plans/README.md`).

## O que eu não quero
- WebView para a interface (a exceção é a feature preview, que é uma página web), .NET ou WinUI.
- Lógica de negócio no app: ela mora no núcleo e chega pela API C (`../../core/include/cadex.h`),
  mesmo o app sendo Zig. Nada de importar arquivo de `../../core/`.
- Pacote de bindings gerados para o Win32.

## Como eu quero
- Zig com Win32, Direct3D 11 no terminal e Direct2D com DirectWrite no resto
  (`../../docs/adr/0012-windows-zig-win32-d3d11.md`).
- Uma pasta por feature em features/, mesmos nomes do núcleo e do Mac; shared/ só com o que 2+
  features usam. Declarações de Win32/COM escritas à mão, só as usadas, em shared/win32.
- Compila neste Mac por cross-compile; roda e testa numa VM Windows 11 ARM (UTM) por ssh.
- Ainda vazio: o plano 9 prepara o núcleo, o plano 10 cria o esqueleto do app.

## Como validar
- Ainda não há o que validar no app; o núcleo no Windows é validado pelo plano 9.

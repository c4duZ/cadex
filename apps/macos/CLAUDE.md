# apps/macos — app Swift

## O que eu quero
- Interface nativa do macOS: AppKit, Metal no terminal, frameworks do sistema para mídia.
- Abrir rápido, gastar pouca memória e ficar leve no disco.

## O que eu não quero
- WebView para a interface (a exceção é a feature preview, que é uma página web).
- Lógica de negócio no Swift: ela mora no núcleo e chega pela API C.

## Como eu quero
- Swift 6 com concorrência estrita. Uma pasta por feature em features/, mesmos nomes do núcleo; shared/ só com o que 2+ features usam.
- Chamadas ao núcleo isoladas numa camada fina por feature.

## Como validar
- `make macos-test` passa.

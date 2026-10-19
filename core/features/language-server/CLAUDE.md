# language-server (núcleo)

## O que eu quero
- Detectar, iniciar, conversar (JSON-RPC sobre stdio) e encerrar language servers.
- Servidores pré-configurados para as linguagens comuns e servidores personalizados.

## O que eu não quero
- Language server ligado sem o usuário pedir.
- Processo de language server sobrando depois de fechar o app.

## Como eu quero
- Um processo por linguagem e raiz de projeto, encerrado ao fechar o app.
- Spec de comportamento em docs/spec/language-server.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- Teste com um servidor falso que responde ao initialize.

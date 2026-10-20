# settings (app Windows)

## O que eu quero
- As mesmas escolhas do Mac, no mesmo formato de settings.json (em %APPDATA%\Cadex), para um arquivo
  servir nas duas máquinas; mudança vale na hora, inclusive editando o arquivo à mão.

## O que eu não quero
- Arquivo quebrado impedindo o app de abrir: campo errado volta ao padrão e vai para o log.

## Como eu quero
- Porta de entrada: `settings.zig`. `model.zig`: Settings com os padrões do Mac, `read` tolerante
  campo a campo e `write` no layout do Mac. `store.zig`: Store (reload, poll pela data do arquivo
  no timer da janela, save atômico).
- Fonte do terminal que o Windows não tem (o "SF Mono" do Mac) cai em Cascadia Mono, pela feature
  terminal.
- Spec: `../../../../docs/spec/settings.md`.

## Como validar
- `make windows-app` compila os testes (ler, escrever, arquivo quebrado); rodam na VM.

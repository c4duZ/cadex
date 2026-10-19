# source-control (núcleo)

## O que eu quero
- Status, diff, stage, unstage, descartar, commit, fetch, pull só fast-forward e push.
- Listar e trocar de branch, saber o upstream e quantos commits à frente e atrás.

## O que eu não quero
- Reimplementar o git: tudo passa pelo binário git do usuário.
- Ação destrutiva (descartar, push) sem o app pedir confirmação antes.
- Comando git sem tempo limite.

## Como eu quero
- Chamar o git como processo, com saída em formato estável (porcelain) e tempo limite.
- Mensagem de erro clara quando o git não está instalado.
- Spec de comportamento em docs/spec/source-control.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- Teste com um repositório temporário cobrindo stage, commit e diff.

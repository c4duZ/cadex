# core/shared — compartilhado do núcleo

## O que eu quero
- Só o que 2 ou mais features do núcleo usam: processos, caminhos, erros, alocação.

## O que eu não quero
- Código de uma feature só morando aqui "porque pode ser útil".

## Como eu quero
- Antes de mover algo para cá, as duas features que usam têm que existir.
- Hoje: `c_buffer.zig` (entregar bytes ao app pela API C, usado por workspace e explorer),
  `ignore.zig` e `glob.zig` (regras de .gitignore, .ignore e .git/info/exclude, como o git: a mais
  funda decide, a última linha vence, nada volta de dentro de pasta ignorada; usado pelo explorer e
  pela busca) e `test_dir.zig` (pasta temporária com caminho canônico, só nos testes).

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.

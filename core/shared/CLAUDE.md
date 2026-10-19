# core/shared — compartilhado do núcleo

## O que eu quero
- Só o que 2 ou mais features do núcleo usam: processos, caminhos, erros, alocação, e a camada fina
  de sistema (Mac e Windows) que elas dividem.

## O que eu não quero
- Código de uma feature só morando aqui "porque pode ser útil".

## Como eu quero
- Antes de mover algo para cá, as duas features que usam têm que existir.
- Hoje: `c_buffer.zig` (entregar bytes ao app pela API C, usado por workspace e explorer),
  `ignore.zig` e `glob.zig` (regras de .gitignore, .ignore e .git/info/exclude, como o git: a mais
  funda decide, a última linha vence, nada volta de dentro de pasta ignorada; usado pelo explorer e
  pela busca), `process.zig` (roda um programa sem shell, com pasta, tempo limite que mata o grupo, saída
  limitada e ambiente extra; usado por source-control e git-history), `regex.zig` (regex POSIX da libc, ADR 0009; usado pela busca e pelos predicados de
  destaque do editor) `test_dir.zig` (pasta temporária com caminho canônico, só nos testes),
  `sync.zig` (mutex e condição: pthread no Mac, SRWLOCK no Windows), `clock.zig` (espera e relógio
  em ms) e `win32.zig` (as funções do Win32 que o núcleo chama, declaradas à mão, ADR 0012).
- Zig 0.16 levou mutex, sleep e relógio do std para o std.Io; o núcleo usa `sync.zig` e
  `clock.zig` em vez de pthread ou usleep direto, para valer nas duas plataformas.

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.

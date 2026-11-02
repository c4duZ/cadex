# core — núcleo em Zig

## O que eu quero
- A lógica que não depende de plataforma, escrita uma vez e usada pelo app macOS, pelo Windows e,
  depois, pelo Linux.
- Uma API C pequena e estável, num header público, como única porta para os apps.

## O que eu não quero
- Código de interface, desenho ou tipos de AppKit aqui.
- Feature importando o miolo de outra: só a porta de entrada.
- Erro virando crash: toda função da API C devolve erro explícito.

## Como eu quero
- Zig (`../docs/adr/0002-zig-core-with-c-api.md`). Uma pasta por feature em features/, e shared/ só com o que 2+ features usam.
- O build junta núcleo, simdutf e highway num único libcadex.a com o `zig ar` (ver `build.zig`).
  Alvo padrão: macOS 13, CPU base (o app roda em outros Macs, não só nesta máquina); num host
  Linux, o alvo padrão é o próprio host com CPU base, para `zig build test` funcionar sem
  `-Dtarget` e o binário rodar em máquinas mais antigas.
- Linux: `shared/fs_posix.zig` usa `renameat2` e uma cópia recursiva própria; o watcher é
  inotify (`features/explorer/watch_linux.zig`); o PTY lê o diretório por /proc e usa o
  `TIOCSWINSZ` do Linux (`features/terminal/pty_posix.zig`). `forkpty` está na libc do glibc
  2.34+ (a base é Ubuntu 24.04/Fedora 44), então não há libutil para ligar.
- Memória: quem aloca libera; a API C deixa claro de quem é cada buffer.
- Funções da API C com prefixo cadex_ e o nome da feature (ex.: cadex_terminal_open).

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.

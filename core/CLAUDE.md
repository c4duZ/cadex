# core — núcleo em Zig

## O que eu quero
- A lógica que não depende de plataforma, escrita uma vez e usada pelo app macOS e, depois, pelo Windows.
- Uma API C pequena e estável, num header público, como única porta para os apps.

## O que eu não quero
- Código de interface, desenho ou tipos de AppKit aqui.
- Feature importando o miolo de outra: só a porta de entrada.
- Erro virando crash: toda função da API C devolve erro explícito.

## Como eu quero
- Zig (`../docs/adr/0002-zig-core-with-c-api.md`). Uma pasta por feature em features/, e shared/ só com o que 2+ features usam.
- Memória: quem aloca libera; a API C deixa claro de quem é cada buffer.
- Funções da API C com prefixo cadex_ e o nome da feature (ex.: cadex_terminal_open).

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.

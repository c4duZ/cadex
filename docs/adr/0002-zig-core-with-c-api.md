# 0002 — Núcleo em Zig, exposto por uma API C

Data: 2026-10-19 · Status: aceita

## Contexto
A lógica que não depende de plataforma (sessões de terminal, arquivos, busca, git, LSP, histórico)
precisa ser escrita uma vez e usada pelo app macOS (Swift) e, depois, pelo app Windows. Foram
considerados C, Rust, Go e Zig.

## Decisão
- O núcleo fica em `core/`, escrito em Zig, e expõe uma API C (um header público).
- O app chama só essa API. Nenhum detalhe interno do Zig vaza para o Swift.

## Por que Zig
- A libghostty-vt (ADR 0003) é Zig: o compilador de Zig já é necessário no projeto, então o custo
  extra é zero.
- Exporta e importa C diretamente, sem gerador de bindings.
- Em modo debug detecta estouro de memória e de inteiro, e o alocador de teste acusa vazamento:
  boa parte da segurança que falta ao C.

## Por que não as outras
- C: mesma interoperabilidade, mas sem nenhuma rede de segurança, e o núcleo lida com dados não
  confiáveis (arquivos do usuário, saída do git, mensagens de language servers).
- Go: leva o runtime e o coletor de lixo para dentro do processo do app; exportar C a partir de Go
  é limitado. O binário também tende a ser maior.
- Rust: viável, mas acrescenta um segundo compilador e uma camada de bindings, sem ganho sobre Zig
  para este projeto.

## Consequências
- Testes do núcleo: `zig build test`, com o alocador de teste ligado para pegar vazamentos.
- Strings, fuzzy match e .gitignore são escritos no núcleo (não há biblioteca pronta equivalente às
  do Rust). Biblioteca C madura pode entrar quando fizer sentido, registrada no `NOTICE`.

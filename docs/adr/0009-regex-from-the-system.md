# 0009 — Regex da busca: a biblioteca do sistema

Data: 2026-10-19 · Status: aceita

## Contexto
A busca de conteúdo (⌘⇧F, `docs/spec/search.md`) aceita expressão regular. O plano 4 pediu para
decidir entre uma biblioteca C madura (PCRE2), a do sistema (POSIX) ou só texto literal no MVP. O
Cadex evita dependência nova sem motivo e quer o app leve.

## Decisão
- Texto literal (o padrão da busca) é procurado pelo próprio núcleo, sem regex.
- Expressão regular usa a biblioteca POSIX da libc do macOS (`regncomp` e `regnexec`, a TRE da
  Apple): sintaxe estendida (ERE), linha por linha, com ou sem caixa. Nada entra no binário.
- Fica sem PCRE2 por enquanto: ela traria ~400 KB e um passo de build em C para recursos (lookahead,
  `\d`, grupos nomeados) que a busca no dia a dia raramente pede. A extensão `REG_ENHANCED` da Apple
  já dá `\d`, `\w`, `\s` e `\b`.

## Consequências
- A sintaxe aceita é a ERE (com as extensões da Apple), não a do Perl/JavaScript; a spec diz isso.
- O app do Windows não tem essa biblioteca: quando chegar a vez dele, a busca escolhe uma (PCRE2 ou
  a própria) atrás da mesma função do núcleo, sem mudar a API C.
- Se a falta de lookahead ou de grupos nomeados incomodar no uso, esta ADR é revista.

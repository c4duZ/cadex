# 0013 — Regex: a TRE compilada no núcleo, a mesma no Mac e no Windows

Data: 2026-10-19 · Status: aceita (substitui a 0009)

## Contexto
A 0009 usava a regex da libc do macOS (`regncomp`, a TRE da Apple). O port para o Windows
(plano 9, fase G) precisa de regex lá também, e a libc do Windows não tem. O critério do plano é a
mesma sintaxe e o mesmo resultado nas duas plataformas: uma busca não pode achar coisa diferente
dependendo do sistema.

## Decisão
- A TRE 0.9.0 (BSD de 2 cláusulas, a mesma base da regex da Apple) é compilada dentro do núcleo,
  pelo `core/build_grammars.zig`, e usada nos dois sistemas atrás de `core/shared/regex.zig`.
- Modo de bytes (sem wchar, sem locale), sem casamento aproximado. É como a regex da libc já se
  comportava no núcleo, que roda no locale "C".
- Sintaxe: a estendida do POSIX (ERE), com `\d`, `\w`, `\s`, os opostos, `\b`, `\<` e `\>` fora de
  colchetes. A API C não muda.

## Por que não as outras
- PCRE2: traz lookahead e grupos nomeados, mas pesa ~400 KB e muda a sintaxe que o Mac já tinha.
- A libc no Mac e outra biblioteca no Windows: duas sintaxes, o contrário do critério.
- Motor próprio: trabalho e risco sem ganho sobre a TRE.

## Consequências
- O binário ganha a TRE (dezenas de KB em ReleaseSmall); ela entra no `NOTICE`.
- Classes como `[[:alpha:]]` e a caixa ignorada valem só para ASCII; acento casa como texto
  literal (o teste de `core/shared/regex.zig` cobre "olá").
- Se a falta de lookahead incomodar no uso, a troca por PCRE2 acontece atrás da mesma função, nas
  duas plataformas de uma vez.

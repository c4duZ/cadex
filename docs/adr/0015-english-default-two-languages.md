# 0015 — Inglês por padrão, português como opção, textos em pares no código

Data: 2026-10-20. Status: aceita.

## Contexto
A interface nasceu em português, escrita direto no código (títulos de comandos, menus,
configurações, mensagens). O dono não usa o Cadex em português e quer o app em inglês por padrão,
com o português como opção nas configurações (2026-10-20). São cerca de 370 frases no Mac e 265 no
Windows, mais as mensagens do núcleo.

## Decisão
- O idioma da interface é uma configuração, general.language ("en" ou "pt"), com inglês por
  padrão. Trocar vale ao reabrir o Cadex: a troca oferece "Reabrir agora", e as abas e os spaces
  voltam. Cada texto é lido uma vez, sem telas que se refazem ao vivo.
- Cada texto é escrito no código como um par, inglês e português, na mesma linha
  (`T("Open file", "Abrir arquivo")` no Swift; o equivalente no Zig). O par fica onde o texto é
  usado, achável no grep pelos dois idiomas, sem chaves nem arquivos de tradução à parte.
- Os ids dos comandos não mudam (estão em inglês desde o começo): settings.json, atalhos e spaces
  continuam valendo. A paleta acha um comando pelo título nos dois idiomas.
- Specs, ADRs, planos e manifestos continuam em português; código e comentários, em inglês.

## Consequências
- Um terceiro idioma pediria trocar os pares por tabelas; com dois, o par é o mais simples de ler e
  de manter, e um texto sem tradução não compila.
- Texto que chega de fora (mensagens do sistema, do git) fica como vier.
- Ordem do trabalho no plano 14 (`docs/plans/14-languages-and-settings.md`).

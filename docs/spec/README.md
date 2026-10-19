# Spec de comportamento

Uma página por feature (`<feature>.md`, mesmo nome da pasta da feature), escrita **antes** de
implementar. É a referência da reescrita: ver `../adr/0004-clean-rewrite.md`.

## O que entra
- O que o usuário vê e faz: telas, estados (vazio, carregando, erro), atalhos, mensagens.
- Regras observáveis: limites, ordem, o que é recusado e por quê.
- Casos de borda que importam (arquivo enorme, binário, sem permissão, sem git instalado).
- Critérios de aceite: frases verificáveis que viram teste.

## O que não entra
- Como o Terax implementa: nomes de funções, arquivos, estruturas internas, trechos de código.
- Decisões de arquitetura do Cadex: essas vão para `../adr/`.

## Modelo de página

```markdown
# <feature>

## Para que serve
<uma ou duas frases, do ponto de vista de quem usa>

## Comportamento
- <o que acontece quando o usuário faz X>

## Estados
- vazio / carregando / erro / pronto: <o que aparece em cada um>

## Casos de borda
- <situação> -> <comportamento esperado>

## Critérios de aceite
- [ ] <frase verificável>
```

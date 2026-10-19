# 0005 — Toda ação é um comando, e o ⌘K executa qualquer um

Data: 2026-10-19 · Status: aceita

## Contexto
O usuário quer fazer tudo pelo teclado, a partir de um único atalho. Se cada botão, menu e atalho
tiver a sua própria implementação, sempre sobra alguma ação que não aparece na paleta, e a paleta
deixa de ser confiável.

## Decisão
- Toda ação do app é um **comando**: um id estável, um título, palavras-chave para a busca, e a
  função que executa. Os comandos ficam num registro único, na feature `command-palette` do app.
- Menus, botões, atalhos e a própria paleta só disparam comandos pelo id. Nenhum deles implementa a
  ação por conta própria.
- ⌘K abre a paleta, de qualquer lugar do app, inclusive com o foco no terminal.
- Limpar o terminal, que nos terminais do Mac costuma ficar em ⌘K, vai para ⌘L (espelha o Ctrl+L dos
  shells).

## Consequências
- Uma ação nova só existe depois de registrada como comando; aparecer na paleta é automático.
- Dá para testar a regra: nenhum menu, botão ou atalho pode apontar para um id que não está no
  registro, e todo comando registrado tem título e pode ser encontrado pela busca.
- Comandos que dependem de contexto (por exemplo, "salvar" só com um editor ativo) dizem quando estão
  disponíveis; a paleta mostra os indisponíveis apagados, com o motivo.
- Não propor tirar ⌘K da paleta para devolver ao "limpar terminal".

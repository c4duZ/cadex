# power (app macOS)

## O que eu quero
- Manter o computador acordado, sempre ou só enquanto um terminal roda um programa, ligado e
  desligado pelo ⌘K (os dois modos) e pelo café no grupo da esquerda da barra de título, que liga o
  modo padrão das configurações (power.mode) ou desliga.
- Com a tampa fechada na tomada, o Mac segue rodando.

## O que eu não quero
- Rodar `caffeinate` ou outro processo: o pedido é do próprio sistema e some se o Cadex cair.
- `pmset disablesleep` (senha de administrador, vale para o sistema todo e fica se o app cair).
- Esta feature olhando terminais: o app diz se algum roda um programa (`anyRunning`).

## Como eu quero
- `PowerController.swift`: a porta de entrada. Modos off, always e running; em running confere os
  terminais a cada 5 s. `keepDisplayOn` vale na hora. `onChange` avisa o ícone.
- `PowerHold.swift`: os pedidos do IOKit (PreventSystemSleep, que vale com a tampa fechada na
  tomada; PreventUserIdleSystemSleep; e o da tela, se pedido). Pedido recusado volta a off.
- `PowerCommands.swift`: power.toggle (⇧⌘A: o modo padrão, `defaultMode`, ou desligar), power.keep-awake, power.keep-awake-while-running e power.allow-sleep; cada
  um some quando não muda nada.
- Spec: `docs/spec/power.md`.

## Como validar
- `make macos-test` passa: sempre, com programa, pedido recusado, comandos que somem.
- No app: ligar e conferir `pmset -g assertions` (o pedido "Cadex: manter o computador acordado").

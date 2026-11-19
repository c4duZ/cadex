# power (app macOS)

## O que eu quero
- Manter o computador acordado, sempre ou só enquanto um terminal roda um programa, ligado e
  desligado pelo ⌘K (os dois modos) e pelo café da barra de status (o item keepAwake, plano 26 fase B; antes na barra de
  título), que liga o
  modo padrão das configurações (power.mode) ou desliga.
- Com a tampa fechada na tomada, o Mac segue rodando.

## O que eu não quero
- Rodar `caffeinate` ou outro processo: o pedido é do próprio sistema e some se o Cadex cair.
- `pmset disablesleep` (senha de administrador, vale para o sistema todo e fica se o app cair).
- Esta feature olhando terminais: o app diz se algum roda um programa (`anyRunning`).

## Como eu quero
- `PowerController.swift`: a porta de entrada. Modos off, always e running; em running confere os
  terminais a cada 5 s. `keepDisplayOn` vale na hora. `onChange` avisa o ícone.
- `hold(job:)` e `release(job:)` (plano 24, fase E): outra feature segura o computador enquanto um
  trabalho dela roda (uma automação, orchestration.keepAwakeDuringRuns), com um pedido próprio,
  sem mudar o modo nem o café; sai com o último trabalho.
- `PowerHold.swift`: os pedidos do IOKit (PreventSystemSleep, que vale com a tampa fechada na
  tomada; PreventUserIdleSystemSleep; e o da tela, se pedido). Pedido recusado volta a off.
- `PowerCommands.swift`: power.toggle (sem atalho desde o plano 29, o ⇧⌘A é do cartão Agent da tela de início: o modo padrão, `defaultMode`, ou desligar), power.keep-awake, power.keep-awake-while-running, power.keep-awake-hour (o "For 1 hour" do cartão do café:
  `keepAwake(for:)` desliga sozinho; `since` e `until` dizem desde quando e até quando) e power.allow-sleep; cada
  um some quando não muda nada.
- Spec: `docs/spec/power.md`.

## Como validar
- `make macos-test` passa: sempre, com programa, pedido recusado, comandos que somem, o trabalho
  de outra feature segurando à parte.
- No app: ligar e conferir `pmset -g assertions` (o pedido "Cadex: manter o computador acordado").

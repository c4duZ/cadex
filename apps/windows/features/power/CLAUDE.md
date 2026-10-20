# power (app Windows)

## O que eu quero
- O manter acordado do Mac: desligado, sempre, ou só com um programa rodando num terminal, pelo
  Ctrl+Shift+K e pelo café na barra de título, com o padrão nas configurações.

## O que eu não quero
- Mudar o plano de energia do Windows (powercfg) ou a opção da tampa: o pedido é do processo e
  some com ele.
- Esta feature olhando terminais: o app diz se algum roda um programa (Host.any_running).

## Como eu quero
- `power.zig`: Power (modo, se segura agora, tela acesa) sobre SetThreadExecutionState
  (ES_SYSTEM_REQUIRED, e ES_DISPLAY_REQUIRED com a tela acesa); `check` roda na conferência de um
  segundo do app. `shouldHold` é a regra pura, testada.
- `commands.zig`: power.keep-awake, power.keep-awake-while-running e power.allow-sleep, os ids do
  Mac; cada um some quando não muda nada.
- Spec: `../../../../docs/spec/power.md`. Referência: `../../../macos/features/power/`.

## Como validar
- `make windows-app` compila os testes; rodam no Windows. No PC: ligar e conferir
  `powercfg /requests` (o Cadex.exe em SYSTEM).

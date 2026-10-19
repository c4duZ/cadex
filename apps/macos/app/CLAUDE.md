# app — entrada do app macOS

## O que eu quero
- Só o ponto de entrada: criar o NSApplication, as janelas e ligar as features.

## O que eu não quero
- Lógica de feature aqui. Cada coisa que a janela mostra vem de uma feature, pela porta de
  entrada dela (os tipos `public` do módulo).

## Como eu quero
- `main.swift` monta a janela com o `TerminalView` da feature terminal e, como delegate, pergunta
  ao terminal antes de fechar a janela ou sair (shouldClose, em
  `../features/terminal/TerminalClose.swift`). Abas, spaces e a paleta
  entram aqui conforme as features existirem.

## Como validar
- `make app` compila; `make run` abre a janela com um shell.

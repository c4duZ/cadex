# app — entrada do app macOS

## O que eu quero
- Só o ponto de entrada: criar o NSApplication, as janelas e ligar as features.

## O que eu não quero
- Lógica de feature aqui. Cada coisa que a janela mostra vem de uma feature, pela porta de
  entrada dela (os tipos `public` do módulo).

## Como eu quero
- `main.swift` registra os comandos de cada feature, monta menu e atalhos a partir deles, e abre a
  janela com as abas (`../features/tabs/TabsController.swift`). Como delegate, pergunta às abas
  antes de fechar a janela ou sair (shouldCloseAll). Abas, spaces e a paleta
  entram aqui conforme as features existirem.

## Como validar
- `make app` compila; `make run` abre a janela com um shell.

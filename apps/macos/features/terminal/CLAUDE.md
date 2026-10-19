# terminal (app macOS)

## O que eu quero
- Desenhar o terminal em Metal, com fonte, cursor, seleção, links e true color.
- Teclado completo, colagem (texto, caminhos de arquivo e imagem como arquivo temporário), arrastar
  arquivos. A ordem da colagem está em `../../../../docs/spec/terminal.md`.
- Busca dentro do terminal.
- Comportamento inicial igual ao terminal do Terax, e de preferência mais leve.
- Texto nítido: desenhado na resolução real da tela, alinhado aos pixels. SF Mono 13 pt por padrão.

## O que eu não quero
- Modo em blocos e terminal privado.
- Lógica de terminal no app: o estado vem do núcleo.
- Redesenhar a tela inteira quando só uma linha mudou.
- Texto borrado: renderizar numa resolução e escalar depois.
- ⌘K indo para o shell: abre a paleta. Limpar a tela é ⌘L.

## Como eu quero
- Só desenha e repassa entrada; fala com a feature terminal do núcleo.
- Teclado: `KeyEncoding.swift` só decide a rota (edição estilo Mac, tecla para o núcleo via
  `cadex_terminal_key`, ou texto pelo sistema de entrada, que compõe acentos). Sequências de
  terminal só na tabela da edição estilo Mac, que é convenção do app. Option esquerdo como Meta
  pelo default "terminal.optionAsMeta" (desligado; a janela de configurações vai gravá-lo).
- Ações do terminal (limpar, buscar, copiar, colar) registradas como comandos.
- Status: janela com um shell, desenho em Metal (SF Mono, nítido), teclado básico e colagem de
  texto, teclas pelo núcleo (modo de aplicação, F-keys, modificadores, kitty, Option como Meta).
  Faltam: seleção, links, busca, rolagem, colagem de arquivos e imagem.

## Como validar
- `make macos-test` passa.

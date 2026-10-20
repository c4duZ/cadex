# 0008 — Ícones Phosphor em todo o app, pela fonte de ícones

Data: 2026-10-19 · Status: aceita; os ícones de tipo de arquivo têm a exceção do 0011

## Contexto
O app precisa de ícones (barra de título, abas, painel lateral, barra de status). O dono escolheu a
família Phosphor (licença MIT) para todo o repositório. O app roda a partir do macOS 13, e o
NSImage só lê SVG a partir do macOS 14.

## Decisão
- Todos os ícones do app são Phosphor, peso regular. Nada de SF Symbols ou de outra família.
  Exceção: o peso fill, do mesmo pacote, para um ícone que mostra ligado (cheio) ou desligado (só o
  contorno), como o de manter acordado (o dono, 2026-10-20).
- Eles vêm da fonte de ícones do pacote oficial (@phosphor-icons/web), registrada pelo app e
  desenhada como imagem modelo, em `apps/macos/shared/icons/`. Funciona no macOS 13, pinta com a cor
  do botão e escala como texto.
- A fonte entra inteira (cerca de 490 KB). Recortar só os ícones usados exigiria uma ferramenta de
  fontes e um passo de geração a cada ícone novo; fica para quando o tamanho pesar.

## Consequências
- Ícone novo é um caso a mais em `Icon.swift`, com o código do glifo da mesma versão do pacote.
- A fonte é um recurso do pacote Swift: o empacotamento do app (plano 7) precisa levar o bundle de
  recursos junto.
- A licença da Phosphor está no `NOTICE`.

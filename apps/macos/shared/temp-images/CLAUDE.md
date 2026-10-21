# temp-images (compartilhado do app)

## O que eu quero
- Imagens PNG que um agente pode abrir pelo caminho, numa pasta da pasta temporária, apagadas
  depois de 7 dias: a imagem colada no terminal (cadex-paste/) e o print do elemento escolhido no
  preview (cadex-pick/).

## O que eu não quero
- Imagem guardada para sempre, ou fora da pasta temporária.

## Como eu quero
- `TempImageStore.swift`: uma pasta e um começo de nome por uso; `save` grava com data e um sufixo,
  `removeOld` apaga as de mais de uma semana. Quem usa chama `removeOld` uma vez por abertura do app.

## Como validar
- `make macos-test` passa: grava PNG, apaga só as antigas, cada uso na sua pasta.

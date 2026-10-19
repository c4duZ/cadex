# search (app macOS)

## O que eu quero
- Abrir arquivo pelo nome e buscar conteúdo no workspace, com resultado aparecendo aos poucos.

## O que eu não quero
- Busca bloqueando a digitação.

## Como eu quero
- Usa a feature search do núcleo; a paleta é a da feature command-palette, por uma fonte própria
  (`PaletteSource`), sem a paleta conhecer a busca.
- Porta de entrada: `SearchController.swift` (as duas fontes sobre a pasta do workspace; trocar a
  raiz ou "mostrar ocultos" refaz o índice, os mesmos valores não) e os comandos search.files (⌘P),
  search.content (⌘⇧F), search.toggle-case (⌥⌘C) e search.toggle-regex (⌥⌘R); os dois
  últimos só valem com a busca de texto aberta, senão a tecla segue para a view.
- `FileSearch.swift`: índice de nomes do núcleo, 50 linhas por consulta, recentes com o campo vazio.
  `ContentSearch.swift`: cada tecla cancela a busca do núcleo e começa outra; os lotes chegam por
  funções C soltas (fora da main actor) e uma caixa que a nova busca desliga, então lote velho não
  aparece. A linha de status mostra as opções ("Aa .*") e a contagem.
- Abrir o escolhido é do app: até os visualizadores (plano 5) vai para o app padrão do sistema, sem a
  linha.
- Spec: `docs/spec/search.md`. Status: plano 4, fase E pronta.

## Como validar
- `make macos-test` passa: ⌘P acha render.zig e não a cópia ignorada, ⌘⇧F entrega linha e caminho,
  regex inválida avisa, consulta nova descarta a velha.
- No app, a paleta só fica aberta com o app na frente (fecha ao perder o foco): conferir à mão.

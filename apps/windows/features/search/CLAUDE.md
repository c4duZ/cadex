# search (app Windows)

## O que eu quero
- As duas buscas do Mac como listas da paleta: arquivo por nome (Ctrl+Shift+P, o ⌘P do Mac; os
  recentes com o campo vazio) e texto nos arquivos (o ⌘⇧F), com os resultados do núcleo, que
  respeita o .gitignore.
- Cada arquivo com o desenho do Material quando o pacote tem (o nome vai em Item.file_name).

## O que eu não quero
- Busca rodando na thread da janela, ou um lote de uma busca velha aparecendo na nova.

## Como eu quero
- Porta de entrada: `search.zig` (Search, Host, filesSource e contentSource para os prefixos `/` e
  `#` da paleta; comandos search.files, search.content, search.toggle-case e
  search.toggle-regex). Cada tecla cancela a busca de texto do núcleo e começa outra; os lotes
  chegam na thread do núcleo numa lista com trava, e um número de geração descarta os antigos.
- Spec: `../../../../docs/spec/search.md`.

## Como validar
- `make windows-app` compila os testes (cadex-search-tests.exe); rodam no Windows.

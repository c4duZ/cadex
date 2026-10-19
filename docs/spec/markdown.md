# markdown

## Para que serve
Ler e escrever as notas do projeto (specs, `CLAUDE.md`, ADRs) no Cadex: ver o Markdown renderizado e,
ao editar, ter links que funcionam entre os arquivos (ADR 0006).

## Comportamento

### Ver
- Um `.md` abre no editor (texto). O comando "Alternar Markdown renderizado" (⇧⌘V) troca para a
  página renderizada e de volta, na mesma aba.
- Renderizado no estilo do GitHub: títulos, ênfase, listas, listas de tarefa, tabelas, citações,
  blocos de código com destaque, linhas horizontais, imagens locais (caminho relativo ao arquivo) e
  links. Cores do tema.
- HTML embutido no Markdown aparece sem script nem estilo que saia da página: nada roda.
- Clicar num link da página: para outro `.md`, abre no Cadex no título certo; para a web, abre no
  navegador; para âncora (`#titulo`), rola até o título.

### Editar
- Ao digitar `](` aparece a lista de arquivos do workspace (busca por nome, como o ⌘P); escolher
  completa o caminho relativo ao arquivo atual. Depois de `#` dentro do link (`](arquivo.md#`), a
  lista mostra os títulos daquele arquivo.
- Ao digitar `[[` aparece a lista de notas (`.md` do workspace, pelo nome sem extensão); escolher
  completa `[[nome]]`.
- ⌘+clique num link (`[x](caminho#titulo)` ou `[[nota]]`) abre o arquivo no título.
- Link quebrado (arquivo que não existe, ou título que não existe no arquivo) fica sublinhado em
  vermelho pontilhado.
- Comando "Quem aponta pra cá": a paleta lista os arquivos do workspace que linkam o arquivo atual,
  com a linha de cada link; escolher abre lá.

### Âncoras
- Formato do GitHub: minúsculas, acentos mantidos, espaços viram `-`, pontuação some (menos `-` e
  `_`); títulos repetidos ganham `-1`, `-2`. "Decisão Final" vira `#decisão-final`.

### Índice
- O núcleo mantém um índice dos `.md` do workspace (títulos e links), atualizado quando arquivos
  mudam no disco. Respeita o .gitignore como a busca.

## Estados
- **Indexando:** primeira leitura do workspace; autocomplete mostra o que já foi lido.
- **Sem resultados:** a lista do autocomplete não aparece.

## Casos de borda
- Link com espaço codificado (`%20`) ou entre `< >` -> resolvido.
- `[[nota]]` com dois arquivos de mesmo nome em pastas diferentes -> vale o mais perto do arquivo
  atual; a lista mostra a pasta para diferenciar.
- Link para fora do workspace -> não é marcado como quebrado nem aberto pelo Cadex.
- Imagem remota (`https://`) no renderizado -> não carrega (sem rede na página).

## Critérios de aceite
- [x] O índice acha link para arquivo, para título, wiki-link, link quebrado e "quem aponta pra cá".
- [x] "Decisão Final" vira `#decisão-final`.
- [x] O HTML renderizado não contém `<script>` nem atributos `on*`.
- [x] Autocomplete de `](` e de `[[` completa o caminho certo.
- [x] ⌘+clique abre o arquivo no título.
- [x] Link quebrado aparece sublinhado.
- [x] ⇧⌘V alterna entre texto e renderizado.

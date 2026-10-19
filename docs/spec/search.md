# search

## Para que serve
Achar um arquivo pelo nome ou um trecho de texto dentro do workspace, sem sair do teclado.

## Comportamento

### Arquivos por nome (⌘P)
- ⌘P abre a paleta no modo "arquivos". O campo filtra os arquivos do workspace por busca aproximada
  (fuzzy) no caminho relativo: "cntrl" acha `core/features/terminal/c_api.zig`.
- O nome do arquivo pesa mais que as pastas do caminho; letras que casaram aparecem em negrito.
- A lista responde a cada tecla, sem esperar a digitação parar.
- Com o campo vazio, mostra os arquivos abertos recentemente.
- Enter abre o arquivo (visualizador do plano 5; até lá, no app padrão do sistema).
- Na paleta do ⌘K, começar o texto com `>` mantém o modo comandos; os modos trocam pelos atalhos.
- A lista de nomes fica em memória e acompanha o disco: arquivo criado aparece, apagado some.

### Conteúdo (⌘⇧F)
- ⌘⇧F abre a paleta no modo "conteúdo". Procura o texto em todos os arquivos do workspace.
- Por padrão, texto literal sem diferenciar caixa. Opções alternáveis: diferenciar caixa e
  expressão regular.
- Resultados chegam aos poucos, agrupados por arquivo: caminho relativo, número da linha e o trecho
  da linha com o que casou em destaque.
- Digitar de novo cancela a busca anterior; resultados da busca velha nunca aparecem.
- Enter abre o arquivo na linha do resultado.
- Limites: até 2 000 resultados (avisa "resultados demais, refine a busca"); arquivos acima de
  2 MB e binários são pulados.

### O que entra na busca
- Respeita `.gitignore` (inclusive os de subpastas e a negação `!`), `.ignore` e o
  `.git/info/exclude`.
- Ocultos ficam de fora, a não ser que "Mostrar arquivos ocultos" esteja ligado. `.git` nunca entra.
- Só dentro do workspace (diretórios autorizados).

## Estados
- **Vazio (arquivos):** recentes; sem recentes, "Digite para buscar arquivos".
- **Indexando:** workspace grande sendo lido pela primeira vez: a lista aparece com o que já foi lido
  e um indicador.
- **Buscando (conteúdo):** indicador enquanto a busca roda; os resultados vão entrando.
- **Sem resultados:** "Nenhum arquivo encontrado" / "Nenhum resultado".
- **Erro de regex:** expressão inválida: a mensagem aparece embaixo do campo, nada é buscado.

## Casos de borda
- Workspace com 100 000 arquivos -> a busca por nome continua respondendo a cada tecla.
- Arquivo com linha de 1 MB -> o trecho mostrado é cortado em volta do que casou.
- `.gitignore` com `build/` e `!build/keep.txt` -> `build/keep.txt` entra, o resto de `build/` não.
- Busca trocada no meio -> a anterior para; nenhum resultado dela aparece depois.
- Arquivo em UTF-8 inválido -> buscado como bytes; o trecho mostra o caractere de substituição.

## Critérios de aceite
- [x] O fuzzy acha "na" em "Nova aba" na frente de "Abrir nova janela" (paleta de comandos).
- [ ] O fuzzy acha "cntrl" em `core/features/terminal/c_api`.
- [ ] `.gitignore` com negação e com pasta aninhada decide certo o que entra.
- [ ] Busca cancelada não entrega resultados velhos.
- [ ] A busca de conteúdo acha texto literal e regex e devolve linha e coluna.
- [ ] ⌘P acha `render.zig` na pasta do Cadex.
- [ ] ⌘⇧F acha "libghostty" e abre o arquivo na linha.

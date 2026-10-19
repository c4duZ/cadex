# command-palette

## Para que serve
Fazer tudo pelo teclado a partir de um atalho só. O ⌘K abre uma busca que acha e executa qualquer
ação do app (ADR 0005). Quando existirem, acha também abas, spaces e arquivos.

## Comportamento

### Comandos
- Toda ação do app é um comando: um id estável em inglês (ex.: `tab.new`, `pane.split-right`), um
  título em português, palavras-chave para a busca e uma condição de disponibilidade.
- Menus, atalhos e botões só disparam comandos pelo id. Uma ação que não está no registro não
  existe.
- O menu da aplicação é montado a partir dos comandos, com o atalho de cada um ao lado.

### Paleta
- ⌘K abre a paleta de qualquer lugar do app, inclusive com o foco no terminal. Nada é enviado ao
  shell.
- A paleta aparece no topo da janela, centralizada: um campo de busca e a lista de resultados
  embaixo. Abre na hora, sem animação perceptível.
- Com o campo vazio, lista em seções com título e ícone: "Recentes" primeiro, depois uma seção por
  área (Abas, Painéis, Arquivos, Busca, Editor, Terminal, Git, Web e mídia, Spaces, Editar, Cadex),
  cada uma em ordem alfabética, com os indisponíveis no fim da seção. O dono sentiu falta das
  seções: a lista plana misturava tudo (2026-10-19).
- Digitar filtra por busca aproximada (fuzzy) no título e nas palavras-chave: "na" acha "Nova aba".
  As letras que casaram aparecem em negrito.
- Digitando, a lista é uma só, pela qualidade da busca, com os indisponíveis no fim.
- Cada linha mostra o ícone da área, o título e, à direita, o atalho do comando desenhado como
  teclas (⇧ ⌘ D), se houver.
- Prefixos no começo do campo trocam a lista sem sair da paleta: `>` comandos, `/` arquivos, `#`
  texto nos arquivos, `@` abas e spaces. O ícone à esquerda do campo mostra a lista da vez.
- Um rodapé mostra as teclas que valem na lista (↩ executar, ↑↓ mover, esc fechar); com o campo
  vazio, também os prefixos.
- Visual com a cara do Cadex: as cores do tema (painel, borda, texto, destaque), cantos de 14 pt,
  a linha selecionada num retângulo arredondado.
- ↑ e ↓ movem a seleção; Enter executa o comando selecionado e fecha a paleta; Esc ou clicar fora
  fecha sem executar. Clicar numa linha executa.
- Comando indisponível no contexto aparece apagado, com o motivo ao lado (ex.: "Fechar painel" sem
  painel aberto). Enter num indisponível não faz nada.
- ⌘K com a paleta aberta fecha a paleta.

### Outras listas
- A mesma paleta mostra arquivos (⌘P) e texto nos arquivos (⌘⇧F), da feature search. O atalho de
  uma lista com ela aberta fecha a paleta; o de outra troca de lista, com o campo vazio.
- À direita do campo, uma nota curta da lista ("Indexando…", "12 resultados").
- Nas listas de arquivos, ↩ abre como a configuração "Abrir arquivos" diz, ⌥↩ abre ao lado e ⌘↩
  abre em nova aba; o rodapé mostra as três. Os arquivos têm o ícone do tipo, como na árvore.

## Estados
- **Vazio:** sem texto, lista recentes e todos os comandos.
- **Sem resultados:** "Nenhum comando encontrado".
- **Pronto:** a lista filtrada, primeiro resultado selecionado.

## Casos de borda
- Busca com acento ou maiúscula: "Divisao" acha "Dividir à direita"; acentos e caixa não importam.
- Comando que falha ao executar: a paleta já fechou; o erro aparece onde a ação aconteceria, não
  na paleta.
- Dois comandos com o mesmo título: os dois aparecem; o id decide qual executa.

## Critérios de aceite
- [x] Todo id usado por menu ou atalho existe no registro.
- [x] Todo comando registrado tem título e é achado pela busca do próprio título.
- [x] A busca "na" ordena "Nova aba" acima de "Abrir nova janela".
- [x] ⌘K com o foco no terminal abre a paleta e não envia nada ao shell.
- [x] Enter executa o comando selecionado; Esc fecha sem executar.
- [ ] Comando indisponível aparece apagado com o motivo e não executa.
- [ ] Campo vazio: seções na ordem da spec, indisponíveis no fim de cada uma.
- [ ] `/` acha arquivos, `#` texto, `@` abas e spaces, `>` volta aos comandos.
- [ ] ⌥↩ num arquivo abre ao lado; ⌘↩, em nova aba.

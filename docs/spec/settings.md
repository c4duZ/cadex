# settings

## Para que serve
Ajustar o Cadex num lugar só: a janela de configurações (⌘,) e o arquivo que guarda as escolhas.

## Comportamento
- ⌘, (ou o comando "Abrir configurações") abre a janela de configurações. Uma só, mesmo chamada
  de novo.
- Seções:
  - **Geral:** shell (vazio usa o do sistema), perguntar antes de fechar com programa rodando,
    perguntar antes de colar várias linhas, e como uma nota Markdown abre: código (padrão) ou
    renderizada (`markdown.openAs`, "source" ou "rendered"), e se a árvore segue a pasta do
    terminal (`explorer.followTerminal`), e onde arquivos abrem: ao lado do painel com foco
    (padrão) ou em nova aba (`general.openFiles`, "beside" ou "tab").
  - **Terminal:** fonte, tamanho, cursor (barra, bloco, sublinhado), cursor piscando, linhas de
    histórico, Option esquerdo como Meta, copiar ao selecionar.
  - **Aparência:** tema (seguir o sistema, ou um tema fixo), imagem de fundo com opacidade e
    desfoque.
  - **Atalhos:** a lista de comandos com o atalho de cada um, editável, com aviso de conflito.
- Toda mudança vale na hora, em todas as janelas, sem botão de salvar.
- As escolhas ficam num arquivo só, `settings.json` em Application Support/Cadex, que o usuário
  também pode editar à mão. Os atalhos personalizados moram nele, na seção `shortcuts`.
- Editar o arquivo com o Cadex aberto também vale na hora.

## Estados
- **Sem arquivo:** valem os padrões; o arquivo nasce na primeira mudança.
- **Arquivo com erro:** valem os padrões para o que estiver errado; o aviso vai para o log e o resto
  do arquivo continua valendo.

## Casos de borda
- Tamanho de fonte fora de 8 a 32 pt: ajustado para o limite mais próximo.
- Histórico acima de 100 mil linhas: limitado a 100 mil (memória).
- Fonte que não existe no sistema: volta para SF Mono, com aviso no log.

## Critérios de aceite
- [x] Preferências salvas e relidas dão os mesmos valores.
- [x] Mudar o tamanho da fonte redesenha os terminais abertos com as novas métricas.
- [x] Um `settings.json` editado à mão com o app aberto vale na hora.
- [x] Um `settings.json` quebrado não impede o app de abrir.
- [x] Sem `general.openFiles` no arquivo, arquivos abrem ao lado; "tab" abre em nova aba.

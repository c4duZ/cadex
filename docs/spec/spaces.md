# spaces

## Para que serve
Separar o trabalho em grupos de abas com nome (um por projeto ou tarefa) e voltar a eles do jeito
que estavam, inclusive depois de fechar ou reabrir o app.

## Comportamento
- A janela mostra um space por vez: as abas da barra são as dele. O nome do space aparece na barra
  de título, à esquerda das abas; clicar nele abre a troca de space.
- "Trocar de space" (⇧⌘S) lista os spaces na paleta, com busca, o atual marcado; escolher um mostra
  as abas dele, com o foco onde estava. "Próximo space" (⌃⌘→) e "Space anterior" (⌃⌘←) andam pela
  ordem de criação, dando a volta.
- "Novo space" cria "Space N" com uma aba de terminal na pasta do workspace e já mostra o novo.
  "Renomear space" pede o nome; vazio volta ao nome que tinha.
- "Fechar space" encerra as abas dele (pergunta antes se algum painel roda um programa ou se há
  arquivo não salvo) e mostra o space anterior. O último space não fecha: o comando fica
  indisponível. Fechar a última aba de um space fecha o space, se houver outro; se for o único,
  fecha a janela, como antes.
- Os programas dos spaces escondidos continuam rodando; só não desenham.
- Ao reabrir o app, cada space volta com as abas na mesma ordem, os nomes dados às abas, as
  divisões com as proporções, a pasta de cada painel, os arquivos e o histórico do git abertos (em
  aba própria ou num painel ao lado de um terminal), o painel com foco, e o space e a aba que estavam ativos. O conteúdo antigo do terminal não volta:
  cada painel começa um shell novo na pasta salva.
- O estado é salvo sozinho, logo depois de cada mudança (abrir, fechar, dividir, mudar de pasta,
  trocar de space), num arquivo em Application Support/Cadex. Fechar o app de surpresa perde no
  máximo o último meio segundo.
- Abrir o app com uma pasta ou arquivos na linha de comando restaura os spaces e abre o que foi
  pedido no space ativo (a pasta ganha uma aba de terminal). Abrir sem pasta (pelo Dock) volta à
  pasta do workspace da última vez.

- Um space pode ter uma cor (space.set-color, ou clique direito no botão do space), salva no
  spaces.json; a cor pinta a barra de abas e o painel lateral enquanto o space aparece
  (`docs/spec/themes.md`, cores de trabalho).

## Estados
- **Primeira abertura (sem arquivo):** um space "Space 1" com um terminal na pasta do workspace.
- **Arquivo ilegível:** como a primeira abertura; o arquivo ruim fica ao lado, com outro nome, para
  não se perder.

## Casos de borda
- Pasta de um painel apagada entre as sessões -> o shell abre na pasta pessoal.
- Arquivo aberto que sumiu -> a aba dele não volta; num painel dividido, o painel vira um terminal
  na pasta do arquivo, para o layout não mudar. O resto volta.
- `spaces.json` de versões anteriores (abas de documento à parte) abre igual.
- Diff, preview web e janelas de mensagem não são restaurados (são passageiros).
- Space salvo sem nenhuma aba -> volta com um terminal.
- Dois spaces com o mesmo nome -> permitido; a paleta mostra a posição.

## Critérios de aceite
- [x] Um space salvo e restaurado volta igual: abas, nomes, divisões com proporções, pastas, foco.
- [x] Arquivo de spaces corrompido não impede o app de abrir: volta ao padrão e guarda o ruim ao lado.
- [ ] Trocar de space pela paleta e pelos atalhos mostra as abas daquele space.
- [x] Fechar o app pelo menu e reabrir traz os mesmos spaces e o mesmo space ativo.
- [x] Um terminal e um documento lado a lado voltam lado a lado.

# computer-use

## Para que serve
Deixar o agente que roda numa aba do Cadex operar outros apps do Mac (abrir, ler o que a janela
mostra, clicar, digitar, rolar, conferir pelo print), com o dono sabendo e permitindo app por app
(`docs/adr/0026-computer-use.md`, plano 20 fase E).

## Comportamento
- Desligado por padrão (`computerUse.enabled`). Ligar (computer-use.toggle, ou em Configurações ›
  Geral › Agentes) mostra o que vai ser pedido e abre os Ajustes do Sistema nas duas permissões do
  Cadex: Acessibilidade (ler e agir em outros apps) e Gravação de Tela (o print de uma janela).
  computer-use.open-permissions abre de novo. Desligado, nenhuma permissão é pedida e as ferramentas
  recusam com "Computer use is off in Cadex".
- As ferramentas chegam ao agente pelo `cadex mcp` (`agent-tools.md`), só nas sessões que o Cadex
  abre:
  - `computer_list_apps`: os apps abertos (nome, id do pacote, se está na frente).
  - `computer_get_state <app>`: a janela da frente do app como árvore (papel, título, valor, se está
    habilitado), cada elemento com um índice (`#1`, `#2`); até 400 elementos e 200 caracteres por
    texto. O índice vale até a próxima leitura daquele app.
  - `computer_click <app> <índice>`, `computer_type <app> <índice> "<texto>"`,
    `computer_set_value <app> <índice> "<valor>"`, `computer_scroll <app> <índice> <direção>`.
  - `computer_screenshot <app>`: o print só da janela do app (nunca da tela inteira), guardado na
    pasta temporária como os prints do preview.
- Permissão por app: a primeira ação num app (ler a árvore conta, listar não) mostra ao dono
  "<agente> quer usar <app>" com Permitir e Negar; a escolha fica em `computerUse.allowedApps`.
  Negado, a ferramenta recusa com "the owner did not allow <app>". computer-use.revoke-apps esquece
  todas as escolhas.
- Bloqueados sempre (recusa sem perguntar): Ajustes do Sistema, Acesso às Chaves, Terminal e o
  próprio Cadex, mais o que o dono puser em `computerUse.blockedApps`.
- Campos de senha (`AXSecureTextField`) aparecem na árvore sem o valor e recusam `type` e
  `set_value`.
- Enquanto o agente age, uma faixa pequena no topo da tela diz "Agente usando <app>" com "Parar"
  (computer-use.stop): para na hora e recusa os pedidos seguintes até o agente começar de novo (o
  primeiro pedido depois do Parar pergunta ao dono de novo).
- O que volta ao agente (títulos, textos, valores) vem marcado como conteúdo do app, não instrução.

## Estados
- **Desligado:** nada pedido, nada ouvindo; as ferramentas recusam.
- **Ligado sem as permissões do sistema:** as ferramentas dizem qual falta e o dono vê o botão para
  abrir os Ajustes.
- **Agindo:** a faixa no topo, com o app e "Parar".
- **Parado pelo dono:** recusa até o agente pedir de novo e o dono permitir.

## Casos de borda
- App fechado entre a leitura e a ação -> "the app is no longer running"; o índice antigo não vale.
- Índice de uma leitura antiga -> "read the state again"; nada é clicado.
- Elemento sem ação de acessibilidade -> o clique vai por evento do sistema no centro dele, com a
  janela na frente.
- Janela minimizada ou em outra mesa -> o app vem para a frente antes da ação.
- Árvore enorme (navegador, planilha) -> cortada nos 400 elementos, com "…" dizendo quantos ficaram de fora.
- O dono revoga a permissão nos Ajustes com o agente agindo -> a próxima ação recusa e a faixa some.

## Critérios de aceite
- [ ] Desligado, nenhuma permissão do sistema é pedida e `computer_list_apps` recusa.
- [ ] Ligado, o agente lê a árvore do TextEdit, digita um texto num documento e confere pelo print.
- [ ] O primeiro uso no TextEdit pergunta ao dono; negar recusa as ações seguintes.
- [ ] Um campo de senha não mostra o valor e recusa digitação; Ajustes do Sistema é recusado sem
      perguntar.
- [ ] "Parar" interrompe na hora: a ação seguinte recusa.
- [ ] O texto lido de outro app chega ao agente marcado como conteúdo.

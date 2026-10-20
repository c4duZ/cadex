# power

## Para que serve
Manter o computador acordado enquanto o trabalho roda (um agente, um build, um servidor), sem um
app à parte como o Amphetamine e sem o comando `caffeinate`. Pedido do dono em 2026-10-20.

## Comportamento
- Três estados: **desligado** (o sistema dorme quando quiser), **sempre** (o computador não dorme
  enquanto o Cadex estiver aberto) e **com programa rodando** (só não dorme enquanto algum
  terminal, em qualquer janela, roda um programa em primeiro plano; com todos parados no shell,
  deixa dormir).
- Pelo ⌘K: "Manter o computador acordado" (sempre), "Manter acordado com programa rodando" e
  "Deixar o computador dormir" (desliga). Cada comando só aparece quando muda alguma coisa: o do
  estado atual some, e "Deixar dormir" só aparece com um dos dois ligado.
- O modo é uma escolha das configurações ou do ⌘K (o dono, 2026-10-20). Nas configurações (Geral):
  "Manter acordado" é o modo padrão, sempre (padrão) ou com programa rodando; "Ligar ao abrir o
  Cadex" já abre ligado nesse modo (padrão não); "Manter a tela acesa" diz se a tela também fica
  acesa (padrão não: a tela pode apagar, o computador segue rodando). No settings.json:
  power.mode ("always" ou "running"), power.onAtLaunch e power.keepDisplayOn. No ⌘K (no Windows,
  Ctrl+Shift+K) os dois modos aparecem, para escolher qualquer um na hora.
- O café fica no grupo da esquerda da barra de título, depois do painel lateral, da busca e dos
  spaces (no Windows, depois da busca), sempre à vista: cheio ligado, só o contorno desligado.
  Clicar liga no modo padrão das configurações, ou desliga se estiver ligado; roda os mesmos
  comandos do ⌘K. Passar o ponteiro diz o estado e o que o clique faz.
- No Mac, o símbolo do Cadex (o C, o > e o _ do logo) fica na barra de menus do macOS, perto do
  relógio, enquanto o Cadex estiver aberto, visível com ele atrás de outros apps: o logo cheio,
  cinza desligado e branco ligado (na barra clara, cinza e preto), e ligado uma chama sai do > do
  logo. O contorno para desligado ficou fino e estranho (o dono, 2026-10-20). Clicar faz o mesmo que o café.
- O que o ⌘K liga vale até desligar ou fechar o Cadex; não muda o padrão das configurações.
- Usa o pedido de energia do próprio sistema (macOS: IOKit; Windows: SetThreadExecutionState),
  que o sistema solta sozinho se o Cadex fechar ou cair: o computador nunca fica preso acordado.
- Tampa fechada (o dono, 2026-10-20): no Mac **na tomada**, o computador segue rodando com a tampa
  fechada (o mesmo pedido do `caffeinate -s`). **Na bateria**, o macOS dorme ao fechar a tampa
  qualquer que seja o pedido; só `pmset disablesleep`, com senha de administrador e valendo para o
  sistema todo, contorna, e fica ligado se o app cair. Fica fora desta versão. No Windows, a tampa
  segue a opção "Ao fechar a tampa" do próprio sistema.

## Estados
- **Desligado:** ícone só com o contorno; o sistema decide.
- **Sempre:** ícone cheio; o computador não dorme por inatividade.
- **Com programa rodando:** ícone cheio; rodando, segura; esperando, o sistema decide.

## Casos de borda
- Programa termina com o estado "com programa rodando" -> em até 5 segundos solta o pedido.
- O pedido do sistema falha -> o estado volta a desligado e o ícone fica só com o contorno.
- Mudar "Manter a tela acesa" com o pedido ativo -> vale na hora, sem desligar.
- Mudar "Ligar ao abrir o Cadex" -> só vale na próxima abertura; o estado atual não muda.
- Mudar o modo padrão com o café ligado -> o estado atual não muda; vale no próximo clique.

## Critérios de aceite
- [ ] "Manter o computador acordado" impede o computador de dormir (`pmset -g assertions` mostra o
  pedido do Cadex) e "Deixar o computador dormir" solta.
- [ ] Com "com programa rodando", `sleep 30` num terminal segura o computador e, ao terminar,
  solta.
- [ ] O café liga no modo padrão e desliga; "Ligar ao abrir o Cadex" abre ligado nesse modo.
- [ ] Fechar o Cadex solta o pedido.
- [ ] Na tomada, com "sempre" ligado, fechar a tampa não interrompe um `ping` que roda no terminal.

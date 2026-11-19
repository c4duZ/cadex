# Plano 37 — As correções da auditoria de UX

O dono, 2026-11-18, depois da auditoria de UX (um agente estudou os princípios, outro passou pelo
app inteiro com eles; o guia está no histórico da sessão): "vamos corrigindo esses 23". O ponto
fraco achado é a atenção (saber que um agente precisa de você); o resto é atrito de nomes, menus e
"onde estou". A estrutura da janela (barra lateral, barra de cima e de baixo) tem um estudo à parte,
docs/design/sidebar/4-auditoria-estrutura.html, e as mudanças de estrutura saem dele, não daqui.

## O que eu quero
- Nunca perder um agente que espera você: um número só para "precisa de você", a mesma fonte para
  todo lugar que mostra estado, e o estado sem sinal ou morto à vista.
- Interromper só pelo que está bloqueado em você.
- Saber onde se está, achar qualquer ação pelo nome, e os atalhos e menus do Mac funcionando como
  no Mac.

## O que eu não quero
- Mudar a estrutura da janela antes do estudo dela.
- Ação visível que não é comando (ADR 0005).

## Como eu quero
- [ ] A. Bugs rápidos: "Remove Task…" do menu da tarefa remove a tarefa clicada; "Update and
  reopen" instala; "Turn On" da Memory diz que liga para todos os projetos; a tela de início sempre
  com Open folder e Clone.
- [ ] B. A atenção: o sino e o Dock contam só o que precisa de você; "terminou sem ver" fica
  quieto (sem banner nem som com o Cadex na frente); o ⌘J vai ao terminal que espera e diz "Nothing
  needs you"; "» N" mostra o estado mais urgente e o de cada aba escondida.
- [ ] C. Um estado só: o trilho com a peça de estado (não só a cor); "servindo" com sinal próprio;
  conversas antigas sem o verde; o estado sem sinal ("unknown") e o agente que morreu trabalhando
  ("failed", com aviso); hibernar aparece no feed.
- [ ] D. Onde estou: o título da janela "projeto › tarefa"; o quadro com título; os ícones das
  páginas apagados sem projeto; o ícone das Automações que não lê como histórico.
- [ ] E. Menus e atalhos: o menu do Mac com Window e Help e os comandos agrupados; aba
  próxima/anterior (⇧⌘] e ⇧⌘[); a gaveta fora do ⌃`; ⌘W num agente sempre pergunta; o ⌘K mostra o
  que não roda agora, apagado, com o motivo; nomes de comando num padrão e sem duplicados.
- [ ] F. Comandos e menus de contexto: Allow e Deny do sino, rodar e apagar automação, apagar
  memória e ir a um projeto como comandos; clique direito nos cartões do quadro, da página Projects,
  nos recentes e nas linhas de Sessions.
- [ ] G. Configurações e textos: o agente de memória avisado na primeira vez e a migração sem
  ligar o que o dono desligou; mensagens que citam seções que não existem; Open PR forte só quando
  faz sentido; caminhos cortados no meio; os termos e o `docs/CONTEXT.md` em dia.

## Como validar
- Os testes de cada feature e `make check`; cada mudança visível conferida numa instância de teste.

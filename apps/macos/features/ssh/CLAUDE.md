# ssh (app macOS)

## O que eu quero
- Os servidores do `~/.ssh/config` à vista: se respondem, e um clique para abrir `ssh <host>` numa
  aba (plano 17, fase E; `../../../../docs/spec/ssh.md`).

## O que eu não quero
- Autenticar, mandar comando ou ler chave: o teste é só uma conexão TCP na porta.
- Testar ou vigiar com ninguém olhando, ou com ssh.ping desligado (a lista continua).
- Dizer "fora do ar" de um host que só se alcança por proxy: esse não é testado.

## Como eu quero
- `SSHConfig.swift`: os hosts, puros e testados: `Host` com nome fixo (curingas, `!` e `Match`
  são regras), `HostName` (com `%h`), `Port`, `ProxyJump`/`ProxyCommand`, `Include` (relativo a
  ~/.ssh, com `*`, sem repetir arquivo, até 8 níveis), `Chave valor` e `Chave=valor`.
- `SSHController.swift`: a porta de entrada, uma para o app (`shared`). `watch`/`stop`; com alguém
  olhando, lê o arquivo, vigia mudanças (escrita, troca atômica do editor, remoção) e testa cada
  host direto (`Network`, 3 s) ao começar e a cada 10 min; `counts` dá o "3/3".
- `SSHCommands.swift`: ssh.connect (a lista de hosts no ⌘K, sem testar nada) e ssh.test-again.
- `SSHStrip.swift`: o item SSH da barra de status: bolinha verde (todos abaixo de 100 ms), amarela
  (algum mais lento), vermelha (algum fora do ar), cinza antes do teste; pulsa só quando não está
  verde ou testando. Passar o ponteiro (ou clicar) abre o cartão (`HoverCard` de
  `../../shared/menus`) com cada host, a cor, o endereço e a resposta; clicar num host conecta,
  "Test Again" testa. Sem menu: o cartão é o caminho (o dono, 2026-10-21).
- O app (`../../app/SSHWiring.swift`) põe o item na barra e faz o ssh.connect (aba nova com `ssh
  '<host>'`).
- Status: fase E no código.

## Como validar
- `make macos-test` passa: hosts, Include, proxy, curingas, nada rodando sem ninguém olhando,
  ssh.ping desligado sem rede, o arquivo relido ao mudar, uma conexão recusada de verdade.

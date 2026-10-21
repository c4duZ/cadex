# ssh

## Para que serve
Ver os servidores do `~/.ssh/config` (as VPS de quem usa), saber se estão no ar e abrir um terminal
num deles com um clique.

## Comportamento
- Os hosts vêm do `~/.ssh/config` (e dos arquivos que ele inclui com `Include`): cada `Host` com
  nome fixo vira um item. `Host` com `*` ou `?` é regra, não servidor, e fica de fora.
- Ao abrir o app, e de novo a cada 10 minutos enquanto o item SSH aparece na barra de status, o
  Cadex testa cada host com uma conexão TCP na porta dele (a 22, ou a do `Port`), com 3 s de limite.
  Não autentica, não manda comando e não lê chave.
- O item da barra de status mostra "SSH 3/3" (no ar/total) com um ponto verde, âmbar se algum caiu,
  cinza antes do primeiro teste. A dica lista cada host com a latência ou "down".
- Clicar no item abre um menu com os hosts: escolher um abre uma aba de terminal com
  `ssh <host>` (comando ssh.connect, com a lista no ⌘K: "SSH: Connect to <host>"). "Test Again"
  testa na hora.
- Mudar o `~/.ssh/config` atualiza a lista sem reabrir o app.

## Estados
- **Sem `~/.ssh/config` ou sem hosts**: o item mostra "SSH" apagado; o menu diz "No hosts in
  ~/.ssh/config".
- **Testando**: o ponto pisca devagar até o primeiro resultado.
- **ssh.ping desligado**: a lista e o "Connect" continuam; nenhum teste de rede.

## Casos de borda
- Host que só resolve por `ProxyJump` ou `ProxyCommand`: não é testado direto (daria um falso
  "down"); aparece como "via <proxy>" e conta como desconhecido.
- `HostName` com variável (`%h`): usa o nome do `Host`.
- Arquivo com erro de sintaxe: o que deu para ler vale; o resto é ignorado em silêncio.

## Critérios de aceite
- [ ] Os hosts do `~/.ssh/config` aparecem no menu, sem os curingas.
- [ ] Desligar a rede faz o item ficar âmbar no próximo teste; "Test Again" volta para verde.
- [ ] Escolher um host abre uma aba nova rodando `ssh <host>`.
- [ ] Com ssh.ping desligado, nenhuma conexão sai do Cadex (conferido com `nettop`).

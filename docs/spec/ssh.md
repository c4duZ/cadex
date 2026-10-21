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
- O item da barra de status mostra "SSH 3/3" (no ar/total) com uma bolinha: verde com todos abaixo
  de 100 ms, amarela com algum mais lento, vermelha com algum fora do ar, cinza antes do primeiro
  teste. Ela pulsa devagar quando amarela, vermelha ou testando; verde fica parada.
- Passar o ponteiro (ou clicar) abre um cartão com cada host: a bolinha dele, o nome, o endereço e a
  resposta ("up 20 ms", "down", "via bastion"). Subir o ponteiro para o cartão o mantém aberto; ele
  fecha quando o ponteiro sai dos dois. Clicar num host abre uma aba com `ssh <host>` (ssh.connect,
  também no ⌘K); "Test Again" testa na hora.
- Mudar o `~/.ssh/config` atualiza a lista sem reabrir o app.

## Estados
- **Sem `~/.ssh/config` ou sem hosts**: o item mostra "SSH" apagado; o cartão diz "No hosts in
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

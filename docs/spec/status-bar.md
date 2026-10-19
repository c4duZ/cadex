# status-bar

## Para que serve
Mostrar, embaixo da janela, onde o terminal com foco está e em que ambiente os processos rodam.

## Comportamento
- À esquerda, a pasta atual da sessão com foco em trilha: "Home › Cadu › Trabalho › cadex". A
  pasta pessoal aparece como "Home".
- Clicar num pedaço da trilha abre um menu com as subpastas daquele nível; escolher uma leva o
  terminal com foco até ela (`cd`), só se o shell estiver parado no prompt. Com um programa rodando,
  o menu mostra as pastas apagadas.
- À direita, o ambiente: "Local" no macOS (no Windows, a distro WSL).
- A barra acompanha o terminal com foco: trocar de aba ou de painel troca a pasta mostrada.

## Estados
- **Pasta desconhecida** (sessão ainda abrindo): a barra mostra só o ambiente.

## Casos de borda
- Caminho longo: os pedaços do meio viram "…" para caber; a pasta atual nunca some.
- Pasta sem permissão de leitura: o menu daquele pedaço fica vazio, com "Sem acesso".

## Critérios de aceite
- [ ] A trilha mostra a pasta do terminal com foco e muda ao trocar de aba.
- [ ] Depois de um `cd` no terminal, a trilha acompanha.
- [ ] Escolher uma subpasta no menu da trilha faz o terminal com foco ir até ela.

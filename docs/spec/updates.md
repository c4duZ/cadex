# updates

## Para que serve
Atualizar o Cadex com um clique, sem rodar o `install.sh` nem baixar o DMG de novo. Pedido do dono
em 2026-10-20, no comportamento do botão de atualização do Terax. Decisão em
`docs/adr/0016-in-app-updates.md`.

## Comportamento
- O Cadex procura versão nova sozinho, em segundo plano: alguns segundos depois de abrir (abrir
  não fica mais lento por isso, o dono, 2026-10-20) e a cada 6 horas enquanto estiver aberto. Sem
  versão nova ou sem internet, não mostra nada.
- Achou versão nova: a janela de atualização abre sozinha, uma vez por abertura do Cadex, com as
  notas e três botões: **Instalar e reabrir**, **Depois** e **Não lembrar de novo** (o dono,
  2026-10-20).
  - **Depois** fecha a janela; ela volta na próxima vez que o Cadex abrir.
  - **Não lembrar de novo**: a janela não abre mais sozinha para essa versão, mas o botão da barra
    fica (o dono, 2026-10-20). Uma versão mais nova volta a abrir a janela.
- Com versão nova, pulada ou não, aparece também um botão na barra de título, à esquerda das
  configurações: uma seta para cima num círculo, na cor de destaque. Passar o ponteiro diz
  "Atualizar para 1.3.0". Sem versão nova, o botão não existe.
- Clicar no botão, ou rodar "Procurar atualizações" no ⌘K (também no menu Cadex), abre uma janela
  pequena que procura na hora e mostra:
  - procurando: "Procurando atualizações…";
  - em dia: "O Cadex está em dia" com a versão instalada, e o botão Fechar;
  - versão nova: "Cadex 1.3.0 disponível", "Você está na 1.2.0", as notas da release e os três
    botões;
  - falha: o que deu errado, numa frase, e os botões Fechar e Tentar de novo.
- "Instalar e reabrir" (também "Instalar atualização" no ⌘K) baixa a versão nova com uma barra de
  progresso (porcentagem e MB), confere, troca o app em Aplicativos e reabre o Cadex. Antes de
  sair, pergunta pelos programas rodando como ao fechar o app; as abas e os spaces voltam.
- Cancelada a saída, a atualização já está instalada: o botão da barra fica, dizendo "Reabrir para
  terminar a atualização", e clicar reabre.
- A versão nova abre sem o aviso "Abrir mesmo assim" e mantém as permissões já dadas ao Cadex.

## Estados
- **Em dia:** nada na barra de título.
- **Disponível:** botão na barra; a janela mostra as notas e "Instalar e reabrir".
- **Baixando:** a janela mostra o progresso; o botão da barra diz a porcentagem.
- **Instalada, falta reabrir:** o botão da barra reabre.
- **Falha:** a janela diz o motivo; nada no app instalado mudou.

## Casos de borda
- Sem internet ou GitHub fora do ar na procura automática -> nada aparece; tenta de novo na próxima.
- O arquivo baixado não confere (SHA-256 ou assinatura) -> "A atualização baixada não confere e não
  foi instalada"; o app instalado fica como estava.
- O app foi aberto direto do DMG ou de Downloads (translocado pelo macOS), ou está numa pasta sem
  permissão de escrita -> a janela explica e pede para mover o Cadex para Aplicativos; não baixa
  nada.
- Rodando fora do pacote .app (`make run`) -> os comandos aparecem indisponíveis ("Só no Cadex
  instalado") e não procura nada.
- A versão publicada é igual ou mais velha que a instalada -> em dia.
- Duas janelas abertas -> um só estado para o app inteiro; o botão aparece em todas.

## Critérios de aceite
- [ ] Com uma release mais nova publicada, a janela de atualização abre sozinha e o botão aparece
  na barra em até alguns segundos depois de abrir.
- [ ] "Não lembrar de novo" faz a janela não abrir mais sozinha para essa versão, nem depois de
  reabrir o Cadex, e o botão da barra continua; uma versão mais nova abre a janela de novo.
- [ ] "Instalar e reabrir" troca o app em /Applications e o Cadex reabre na versão nova, com as
  mesmas abas, sem "Abrir mesmo assim".
- [ ] Um `latest.json` com assinatura errada é recusado e o app instalado não muda.
- [ ] "Procurar atualizações" com o app em dia diz "O Cadex está em dia".
- [ ] Aberto do DMG montado, explica que precisa estar em Aplicativos.

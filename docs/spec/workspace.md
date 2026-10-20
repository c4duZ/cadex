# workspace

## Para que serve
Dizer em qual pasta o usuário está trabalhando (a raiz do explorer e da busca) e garantir que o app
só mexe em arquivos dentro das pastas que o usuário abriu.

## Comportamento
- **Workspace** é a pasta raiz aberta na janela. O explorer mostra a árvore dela e a busca procura
  dentro dela.
- O workspace é definido:
  - ao abrir o app com uma pasta: pela linha de comando (`Cadex /caminho`) ou arrastando a pasta no
    ícone do Dock; com um arquivo, ele abre numa aba e, se estiver fora do workspace, a pasta dele
    vira o workspace;
  - pela paleta, com "Abrir pasta…", que mostra o seletor de pastas do sistema;
  - pela paleta, com "Usar a pasta do terminal", que pega a pasta atual do painel com foco;
  - sozinho, seguindo o terminal: quando a pasta do terminal com foco muda (`cd`), o workspace vai
    para o projeto dela, a raiz do repositório git onde ela está ou a própria pasta fora de um.
    `cd src` dentro de um projeto não troca o workspace. A opção "A árvore segue o terminal"
    (explorer.followTerminal, ligada por padrão) desliga. O dono deu `cd` e a árvore ficou na pasta
    pessoal (2026-10-19).
- Sem nenhuma dessas, o workspace é a pasta pessoal do usuário.
- No Windows, o **ambiente** dos terminais novos é Local (o próprio Windows) ou uma distro do WSL,
  escolhido pela paleta ("Escolher o ambiente dos terminais"). Um terminal numa distro abre o shell
  dela na mesma pasta; a pasta que ele avisa (/home/ana) vira \\wsl.localhost\<distro>\home\ana
  para a árvore e a barra de status, que mostra o nome da distro.
- Toda pasta que vira workspace entra na lista de **diretórios autorizados**. Ler, listar, criar,
  renomear, mover, copiar, apagar e buscar só valem dentro de um diretório autorizado (ou de uma
  subpasta dele).
- Antes de comparar, todo caminho é resolvido: `..`, `.`, barras repetidas e links simbólicos viram o
  caminho real. Um link dentro do workspace que aponta para fora conta como fora.
- Um caminho que ainda não existe (arquivo a criar) é aceito se a pasta que vai contê-lo, resolvida,
  está dentro de um diretório autorizado.
- A lista de autorizados dura enquanto o app está aberto. Trocar de workspace não tira a pasta
  anterior da lista nessa sessão.
- **Várias janelas.** "Nova janela" (⌘N) abre outra janela com um terminal na pasta do workspace
  da janela com foco. Cada janela tem o próprio workspace, os próprios spaces e abas, e o seu
  explorer, busca e git: trocar a pasta numa não mexe na outra. Menus, atalhos e a paleta agem na
  janela com foco. Pedido do dono em 2026-10-20.
- Só a **janela principal** (a que abriu com o app) é salva e restaurada pelos spaces. As outras
  são passageiras: fechar o app ou a janela não guarda nada delas. Fechada a principal, nenhuma
  outra toma o lugar dela; o arquivo fica com o que ela tinha ao fechar.
- Fechar uma janela pergunta só pelos programas e arquivos dela. Sair do app pergunta uma vez por
  todas as janelas. Fechada a última janela, o app sai.
- O comando `cadex` no terminal (abrir pasta pelo shell) fica fora do MVP (ADR 0007).

## Estados
- **Pronto:** um workspace definido; o título do explorer mostra o nome da pasta.
- **Pasta sumiu:** o workspace foi apagado ou desmontado com o app aberto; o explorer mostra a pasta
  como indisponível e oferece "Abrir pasta…".

## Casos de borda
- `/workspace/../etc/passwd` -> recusado (resolve para fora).
- `/workspace/link` com `link -> /etc` -> recusado.
- `/workspace-irmao/arquivo` (prefixo de texto igual, outra pasta) -> recusado: a comparação é por
  componente de caminho, não por prefixo de texto.
- Caminho relativo vindo do app -> recusado: o app sempre manda caminho absoluto.
- Autorizar `/` -> aceito só se o usuário escolheu `/` de fato no seletor.
- Autorizar uma pasta que não existe -> erro, a lista não muda.

## Critérios de aceite
- [x] Caminho com `../` que sai do workspace é recusado.
- [x] Link simbólico dentro do workspace apontando para fora é recusado.
- [x] Pasta irmã com o mesmo prefixo de nome é recusada.
- [x] Arquivo ainda inexistente numa pasta autorizada é aceito.
- [x] O app abre na pasta passada pela linha de comando.
- [ ] "Abrir pasta…" pela paleta troca o workspace e o explorer (falta conferir à mão: abre o seletor do sistema).
- [x] "Usar a pasta do terminal" troca o workspace para a pasta do painel com foco.
- [x] Um terminal dentro de um repositório leva a árvore para a raiz do repositório.
- [ ] ⌘N abre outra janela na pasta do workspace da janela com foco (macOS; no Windows o comando abre outro processo, sem atalho).
- [ ] Trocar a pasta, o space ou a aba numa janela não muda a outra.
- [ ] Sair e abrir de novo traz só a janela principal.

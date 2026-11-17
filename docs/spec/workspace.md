# workspace

## Para que serve
Montar a janela (as regiões da moldura), dizer em qual pasta o usuário está trabalhando (a raiz do
explorer e da busca) e garantir que o app só mexe em arquivos dentro das pastas que o usuário abriu.

## Comportamento
### A janela
- Toda tela tem a mesma moldura, em quatro regiões (`../adr/0035-work-frame.md`; o mapa em
  `../design/work-frame/screens.md`, seção Map; tokens components.window, components.titleBar e
  components.statusBar):
  - **barra de título** (44 pt): os botões da janela, a busca ⌘K, "projeto › tarefa", as abas
    (`tabs.md`), e à direita o quadro, o sino e o botão do painel da direita. O café, a atualização
    e as configurações não ficam nela: o café e a atualização vão para a barra de status
    (`status-bar.md`), as configurações ficam no ⌘, e no menu;
  - **esquerda:** a árvore do trabalho (`sidebar.md`), recolhível (⌘B);
  - **centro:** o que se abriu: os terminais e documentos da seleção, a página do projeto, o quadro,
    a corrida, a tela de início (`home.md`); a gaveta de terminais sobe por cima dele (⌃`);
  - **direita:** o painel da seleção (`inspector.md`), opcional (⌥⌘I);
  - **barra de status** embaixo (30 pt).
- A janela tem cantos de 12 e o fundo da moldura nova; a imagem de fundo e a vibrância, quando
  ligadas, continuam como antes (`themes.md`).

### A pasta
- **Workspace** é a pasta da seleção: a do projeto, ou a da tarefa (a worktree) quando uma tarefa
  está selecionada (`projects.md`). O explorer mostra a árvore dela e a busca procura
  dentro dela.
- O workspace é definido:
  - ao abrir o app com uma pasta: pela linha de comando (`Cadex /caminho`) ou arrastando a pasta no
    ícone do Dock; com um arquivo, ele abre numa aba e, se estiver fora do workspace, a pasta dele
    vira o workspace;
  - pela paleta, com "Abrir pasta…", que mostra o seletor de pastas do sistema;
  - pela paleta, com "Usar a pasta do terminal", que pega a pasta atual do painel com foco;
  - sozinho, seguindo o terminal: quando a pasta do terminal com foco muda (`cd`), o workspace vai
    para a raiz do repositório git onde ela está, ou para a própria pasta fora de um (`cd ~`,
    `cd /tmp`). Em 2026-10-20 a árvore deixou de seguir fora de repositórios, por medo do peso da
    pasta pessoal; o dono pediu de volta (2026-10-21), e os índices já ficam leves nela (começam na
    primeira busca e leem perto do terminal primeiro). `cd src` dentro de um projeto não troca o
    workspace. A opção "A árvore segue o terminal"
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
- **Várias janelas.** "Nova janela" (⇧⌘N; o ⌘N é Nova tarefa, plano 29) abre outra janela com um terminal na pasta do workspace
  da janela com foco. Cada janela tem o próprio workspace, os próprios projetos e abas, e o seu
  explorer, busca e git: trocar a pasta numa não mexe na outra. Menus, atalhos e a paleta agem na
  janela com foco. Pedido do dono em 2026-10-20.
- Só a **janela principal** (a que abriu com o app) é salva e restaurada pelos projetos. As outras
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
- [ ] Toda tela tem as mesmas quatro regiões, com as medidas dos tokens (conferido lado a lado com
  os mockups).
- [ ] ⇧⌘N abre outra janela na pasta do workspace da janela com foco (macOS; no Windows o comando abre outro processo, sem atalho).
- [ ] Trocar a pasta, o projeto ou a aba numa janela não muda a outra.
- [ ] Sair e abrir de novo traz só a janela principal.

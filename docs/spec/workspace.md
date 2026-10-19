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
  - pela paleta, com "Usar a pasta do terminal", que pega a pasta atual do painel com foco.
- Sem nenhuma dessas, o workspace é a pasta pessoal do usuário.
- Toda pasta que vira workspace entra na lista de **diretórios autorizados**. Ler, listar, criar,
  renomear, mover, copiar, apagar e buscar só valem dentro de um diretório autorizado (ou de uma
  subpasta dele).
- Antes de comparar, todo caminho é resolvido: `..`, `.`, barras repetidas e links simbólicos viram o
  caminho real. Um link dentro do workspace que aponta para fora conta como fora.
- Um caminho que ainda não existe (arquivo a criar) é aceito se a pasta que vai contê-lo, resolvida,
  está dentro de um diretório autorizado.
- A lista de autorizados dura enquanto o app está aberto. Trocar de workspace não tira a pasta
  anterior da lista nessa sessão.
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

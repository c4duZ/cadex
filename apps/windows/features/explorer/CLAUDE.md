# explorer (app Windows)

## O que eu quero
- A árvore do workspace do Mac no painel lateral: lida pelo núcleo pasta a pasta, seguindo o disco,
  pastas abertas lembradas por raiz, renomear no lugar, menu de contexto, arrastar para o terminal,
  cores e letras do git, e os comandos do Mac com os mesmos ids.
- Os desenhos do Material Icon Theme para arquivos e pastas que ele conhece, como no Mac
  (`../../../../docs/adr/0011-material-file-icons.md`); o resto em Phosphor.

## O que eu não quero
- Operação de arquivo fora do workspace autorizado no núcleo, ou lendo o disco na thread da janela
  sem passar pelo núcleo.
- Ação que só existe na tecla da árvore ou no menu: os dois rodam os comandos por id.

## Como eu quero
- Porta de entrada: `explorer.zig` (Explorer, Host: abrir arquivo, cd no terminal, pasta do
  terminal, letra do git, acordar a janela, pastas mudadas; setRoot autoriza a raiz no núcleo).
- `tree.zig`: o modelo (nós lidos ao abrir, pastas compactas, recarga que mantém o que estava
  aberto). `view.zig`: o desenho no estilo do VS Code e o mouse e as teclas da árvore; o menu de contexto pelo tipo (pasta: terminal e Explorador; arquivo: as formas de abrir), sem o que não roda (available, em `commands.zig`).
  `watcher.zig`: o observador do núcleo, entregue à janela por `drain`. `actions.zig`: o que cada
  comando faz (Lixeira pelo SHFileOperationW com desfazer). `commands.zig`: a tabela dos comandos
  (explorer.* e workspace.*). `expanded_store.zig`: %APPDATA%\Cadex\explorer.json.
- Spec: `../../../../docs/spec/explorer.md` e `../../../../docs/spec/workspace.md`.
- Altura das linhas por `rowPx` (densidade compacta, plano 15) e o texto da linha selecionada em
  `tab_active_text`, legível sobre o destaque.

## Como validar
- `make windows-app` compila os testes (cadex-explorer-tests.exe); rodam no Windows.
- No Windows: abrir uma pasta com src, .github e um Dockerfile mostra os desenhos do Material;
  criar, renomear e apagar pelo Explorador do Windows atualiza a árvore.

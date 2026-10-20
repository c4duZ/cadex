# terminal (app Windows)

## O que eu quero
- O terminal do Mac no Windows: um shell por painel pelo núcleo (ConPTY), texto nítido em qualquer
  escala, teclado com ABNT2, acentos, AltGr e IME, mouse, links com Ctrl, busca e colagem.

## O que eu não quero
- Lógica de terminal aqui: codificar teclas, seleção, links e colagem são do núcleo.
- Atalho do app roubando Ctrl+letra do shell; tecla tratada chegando duas vezes (o WM_CHAR dela).
- Bloquear a janela com saída enorme: a thread de leitura só avisa (Events.post) e a janela desenha.

## Como eu quero
- Porta de entrada: `terminal.zig` (SharedFont, uma fonte para todos os painéis).
- `session.zig`: Session, a cadex_terminal com as preferências e os avisos da thread de leitura
  (saída agrupada, fim, título, sino, servidor local), que quem segura recebe por Events.post e
  trata na thread da janela.
- `view.zig`: View, um painel: ajusta colunas e linhas ao retângulo (padding de 8 pt), desenha,
  mouse (seleção com duplo e triplo clique e Shift, autoscroll, roda de 3 linhas por entalhe,
  programas que pedem o mouse, Shift força a seleção), Ctrl+passar sublinha links e Ctrl+clique
  abre (Hooks.open_link). `keyDown` recebe as teclas antes do TranslateMessage: teclas com nome e
  Ctrl/Alt vão ao núcleo (`keys.zig`); o resto chega como texto pelo WM_CHAR (`typeText`).
- `renderer.zig`: o quadro do núcleo na ordem do Mac (fundos, seleção, buscas em âmbar e laranja,
  cursor de bloco com o texto na cor do fundo, glifos em runs por face e cor, sublinhados, cursores
  finos, barra de rolagem); célula que a fonte não tem (emoji) vai por layout do DirectWrite.
- `font.zig`: Font (as quatro faces, a célula em pixels inteiros, cache de glifos); fonte que o
  Windows não tem cai em Cascadia Mono; tamanho em pontos (4/3 de pixel a 96 dpi).
- `find.zig`: a barra de busca ("3 de 12", Enter, Shift+Enter, Esc). `paste.zig`: arquivos, imagem
  (PNG em %TEMP%\cadex-paste, apagada depois de 7 dias) e texto, com a pergunta de várias linhas.
- Spec: `../../../../docs/spec/terminal.md`.

## Como validar
- `make windows-app` compila os testes desta feature; vim, htop do WSL, acentos no ABNT2, IME e
  colagem conferidos na VM.

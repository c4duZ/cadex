# terminal (núcleo)

## O que eu quero
- Abrir, redimensionar e fechar sessões de shell num PTY, com o shell padrão do usuário.
- Alimentar a libghostty-vt com a saída e expor ao app a grade, o cursor, os modos e o scrollback.
- Integração de shell (OSC 7 e OSC 133) para saber o diretório atual e os blocos de comando.
- Saber se uma sessão tem um processo rodando em primeiro plano (para avisar antes de fechar).

## O que eu não quero
- Qualquer outra feature, do núcleo ou do app, falando direto com a libghostty.
- Processo do shell sobrevivendo ao fechamento da sessão.
- Saída do terminal sendo copiada para o app quadro a quadro sem necessidade.

## Como eu quero
- Toda chamada à libghostty-vt mora aqui; a porta de entrada expõe tipos nossos.
- Leitura do PTY fora da thread do app, com fila limitada (backpressure).
- Spec de comportamento em docs/spec/terminal.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- Teste que abre um shell, escreve um comando e lê a saída de volta.

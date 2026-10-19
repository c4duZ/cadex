# explorer (app macOS)

## O que eu quero
- Árvore de arquivos com ícones, busca, navegação por teclado, renomear inline e ações de contexto.
- Atualização ao vivo quando o disco muda; marcar arquivos alterados no git.

## O que eu não quero
- Ler o disco direto do Swift: tudo passa pela feature explorer do núcleo.

## Como eu quero
- Árvore carregada sob demanda, pasta por pasta.
- Spec de comportamento em docs/spec/explorer.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make macos-test` passa.

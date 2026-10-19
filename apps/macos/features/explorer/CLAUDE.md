# explorer (app macOS)

## O que eu quero
- Árvore de arquivos com ícones, busca, navegação por teclado, renomear inline e ações de contexto.
- Atualização ao vivo quando o disco muda; marcar arquivos alterados no git.

## O que eu não quero
- Ler o disco direto do Swift: tudo passa pela feature explorer do núcleo.

## Como eu quero
- Árvore carregada sob demanda, pasta por pasta.
- A raiz da árvore é o workspace: `WorkspaceFolder.swift` guarda a pasta aberta (a da linha de
  comando, senão a pasta pessoal), autoriza no núcleo cada pasta que vira raiz e avisa a troca por
  `onChange`. A feature workspace não tem pasta no app; a parte dela que o usuário vê mora aqui.
- Comandos em `WorkspaceCommands.swift`: `workspace.open-folder` ("Abrir pasta…", ⌘O, seletor do
  sistema) e `workspace.use-terminal-folder` (a pasta do terminal com foco, que `apps/macos/app/main.swift`
  passa por closure: o explorer não vê terminais).
- Spec: `docs/spec/explorer.md` e `docs/spec/workspace.md`. Status: workspace pronto (plano 4,
  fase A); a árvore é a fase C. Até lá o painel lateral mostra o nome da pasta.

## Como validar
- `make macos-test` passa.

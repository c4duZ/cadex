# themes (app macOS)

## O que eu quero
- Temas prontos e criados pelo usuário, com importar e exportar; imagem de fundo com opacidade e
  desfoque.
- Importar os temas do Terax: o usuário traz os temas que já usa.
- Tema do editor independente do tema do app.

## O que eu não quero
- Transparência ligada por padrão (custa desempenho).
- Descobrir o formato dos temas do Terax lendo o código dele (ADR 0004). O formato é levantado a partir
  de arquivos de tema exportados pelo próprio app.

## Como eu quero
- O importador converte o tema do Terax para o formato do Cadex; o Cadex só guarda o formato dele.
- `ThemeCatalog.swift`: os 46 temas embutidos, de `Resources/catalog.json`, gerado por
  `../../../../tools/themes/build_catalog.py` (não editar à mão). `ThemeFamily.swift`: um tema com
  versão escura e/ou clara, e o modo (sistema, escuro, claro). Padrão: Caffeine.
- `Theme.swift`: o tema (cores da interface e do terminal, 16 ANSI). `BuiltInThemes.swift`: Cadex
  Escuro (cores da interface medidas num print do Terax) e Cadex Claro. `ThemeStore.swift`: o tema
  em uso, seguindo o modo do sistema, e quem observa a troca. `ThemeFile.swift`: o arquivo JSON do
  tema (ler com validação que cita o campo, escrever).
- As cores do terminal chegam a ele pelo `TerminalAppearance` da feature terminal, que o app
  preenche a partir do tema; a feature terminal não depende desta.
- Spec em `../../../../docs/spec/themes.md`. Status: temas embutidos, troca pelo sistema, arquivo
  JSON, cores no terminal e catálogo prontos; galeria nas configurações, importar e imagem de fundo
  a fazer.

## Como validar
- `make macos-test` passa.
- Teste: importar temas exportados do Terax (arquivos de exemplo na pasta de testes) gera as mesmas
  cores.

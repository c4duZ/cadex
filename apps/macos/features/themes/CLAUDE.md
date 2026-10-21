# themes (app macOS)

## O que eu quero
- Temas prontos e criados pelo usuário, com importar e exportar; imagem de fundo com opacidade e
  desfoque.
- Tema do editor independente do tema do app.

## O que eu não quero
- Transparência ligada por padrão (custa desempenho).
- Copiar arquivos ou código do Terax (ADR 0004): os temas embutidos vêm das fontes abertas originais.

## Como eu quero
- `ThemeCatalog.swift`: os temas embutidos (centenas, `../../../../docs/adr/0017-base16-themes.md`),
  de `Resources/catalog.json`, gerado por `../../../../tools/themes/build_catalog.py` (não editar à
  mão), lidos quando pedidos e não guardados: `all()` para a página e o ⌘K, `family(id:)` para o
  tema em uso. `ThemeLibrary.swift`: os temas do usuário (pasta Application Support/Cadex/themes,
  ids "user:", primeiro na lista; arquivo quebrado vira problema com o motivo; CADEX_THEMES_DIR nos
  testes) e o catálogo. `ThemeImport.swift`: .itermcolors, Ghostty, base16/base24 (.yaml) e .json;
  a interface de um tema só de terminal sai do fundo, do texto e do azul dele. A aba ativa é a cor da barra de título
  com 22% da cor principal do tema: o "accent" do tweakcn sólido pintava de âmbar ou verde, e cinza
  neutro deixava todos os temas iguais. A cor principal aparece também nas pastas, na seleção da
  árvore e no ícone da aba ativa. `ThemeFamily.swift`: um tema com
  versão escura e/ou clara, e o modo (sistema, escuro, claro). Padrão: Caffeine.
- `Theme.swift`: o tema (cores da interface e do terminal, 16 ANSI). `BuiltInThemes.swift`: Cadex
  Escuro (cores da interface medidas num print do Terax) e Cadex Claro. `ThemeStore.swift`: o tema
  em uso (só a família dele fica na memória), seguindo o modo do sistema, e quem observa a troca. `ThemeFile.swift`: o arquivo JSON do
  tema (ler com validação que cita o campo, escrever).
- As cores do terminal chegam a ele pelo `TerminalAppearance` da feature terminal, que o app
  preenche a partir do tema; a feature terminal não depende desta.
- Spec em `../../../../docs/spec/themes.md`. Status: temas embutidos, troca pelo sistema, arquivo
  JSON, cores no terminal, catálogo, galeria nas configurações, imagem de fundo e vibrância prontos.
  Importar temas do Terax saiu do plano.

## Como validar
- `make macos-test` passa.
- Teste: o catálogo tem mais de 300 temas, o Caffeine primeiro, todos com texto legível; os do
  tweakcn com ANSI próprio; importar Ghostty, iTerm2 e base16; a pasta do usuário.

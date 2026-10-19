# themes (app macOS)

## O que eu quero
- Temas prontos e criados pelo usuário, com importar e exportar; imagem de fundo com opacidade e
  desfoque.
- Tema do editor independente do tema do app.

## O que eu não quero
- Transparência ligada por padrão (custa desempenho).
- Copiar arquivos ou código do Terax (ADR 0004): os temas embutidos vêm das fontes abertas originais.

## Como eu quero
- `ThemeCatalog.swift`: os 46 temas embutidos, de `Resources/catalog.json`, gerado por
  `../../../../tools/themes/build_catalog.py` (não editar à mão). A aba ativa e o campo são neutros
  (a cor da barra de título misturada ao texto): o "accent" do tweakcn pintava de âmbar ou verde. `ThemeFamily.swift`: um tema com
  versão escura e/ou clara, e o modo (sistema, escuro, claro). Padrão: Caffeine.
- `Theme.swift`: o tema (cores da interface e do terminal, 16 ANSI). `BuiltInThemes.swift`: Cadex
  Escuro (cores da interface medidas num print do Terax) e Cadex Claro. `ThemeStore.swift`: o tema
  em uso, seguindo o modo do sistema, e quem observa a troca. `ThemeFile.swift`: o arquivo JSON do
  tema (ler com validação que cita o campo, escrever).
- As cores do terminal chegam a ele pelo `TerminalAppearance` da feature terminal, que o app
  preenche a partir do tema; a feature terminal não depende desta.
- Spec em `../../../../docs/spec/themes.md`. Status: temas embutidos, troca pelo sistema, arquivo
  JSON, cores no terminal, catálogo, galeria nas configurações, imagem de fundo e vibrância prontos.
  Importar temas do Terax saiu do plano.

## Como validar
- `make macos-test` passa.
- Teste: o catálogo embutido carrega os 46 temas, o Caffeine primeiro.

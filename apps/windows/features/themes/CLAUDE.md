# themes (app Windows)

## O que eu quero
- Os mesmos temas do Mac (centenas: oficiais, tweakcn, base16 e base24), lidos do mesmo catalog.json
  (`../../../macos/features/themes/Resources/catalog.json`, embutido pelo build), Caffeine padrão,
  seguindo o claro/escuro do Windows por padrão.
- Os temas do usuário em %APPDATA%\Cadex\themes (ao lado do settings.json), um tema do Cadex em
  JSON por arquivo, com id `user:<nome do arquivo>`, listados antes dos do catálogo; e importar
  .itermcolors, tema do Ghostty, base16/base24 (.yaml) e .json, como o Mac.

## O que eu não quero
- Cópia do catálogo dentro de apps/windows.
- O catálogo inteiro guardado na memória: o Store guarda só a família em uso; a lista de todos é
  lida por quem a mostra e liberada quando some da tela (plano 15: centenas de temas sem pesar).
- A descrição de cada tema passando pelo t do módulo strings (a tabela de pares é dos textos fixos do app).

## Como eu quero
- Porta de entrada: `themes.zig` (Store: família e modo escolhidos, num arena próprio trocado a cada
  tema; `select` só lê o arquivo quando o id muda; `reload` depois de importar; `refresh` quando o
  Windows troca de modo; `style` para a camada de interface; `terminalColors` para o núcleo).
- `theme.zig`: Theme, Family (com `source`), Problem (o campo errado e por quê), a leitura de cada
  versão (cores #RGB, #RRGGBB, #RRGGBBAA; 16 ANSI), `mix` e `luminance` como o RGB do Mac.
- `catalog.zig`: o catálogo embutido lido sob demanda (`appendAll`, `find`), a árvore do JSON
  liberada antes de voltar; a descrição no idioma da interface.
- `library.zig`: a pasta do usuário e o catálogo juntos (`all` devolve uma List com arena própria e
  os problemas "arquivo: campo: motivo"; `family` por id; `save` com o nome do arquivo pelo nome do
  tema).
- `file.zig`: o arquivo de tema do Cadex (ThemeFile.swift), ler e escrever.
- `import.zig`: .itermcolors, Ghostty, base16/base24 e .json, com o mapeamento e as cores de
  interface derivadas iguais às do ThemeImport.swift; amostras em `import_tests.zig`.
- O modo do sistema vem do registro (AppsUseLightTheme); o app relê em WM_SETTINGCHANGE.
- Spec: `../../../../docs/spec/themes.md`.

## Como validar
- `make windows-app` compila os testes (o catálogo tem mais de 300 temas com Caffeine primeiro, a
  busca por id, cada importador, salvar e achar na pasta do usuário); rodam no PC Windows.
  Os de `import.zig`, `file.zig` e `catalog.zig` só usam std e strings, e rodam também no Mac com
  `zig test`.

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
- O catálogo inteiro guardado na memória: o Store guarda só as famílias em uso (a do escuro e a do claro); a lista de todos é
  lida por quem a mostra e liberada quando some da tela (plano 15: centenas de temas sem pesar).
- A descrição de cada tema passando pelo t do módulo strings (a tabela de pares é dos textos fixos do app).

## Como eu quero
- Porta de entrada: `themes.zig` (`style` para a camada de interface, com o texto sobre a aba ativa;
  `terminalColors` para o núcleo). `store.zig`: Store (plano 15, fase B), uma família para o escuro e
  outra para o claro, cada uma num arena próprio trocado com ela (o mesmo id é copiado, não relido),
  o modo, o destaque e o alto contraste; `apply` com a Choice das configurações só lê arquivo quando
  um id muda; `reload` depois de importar; `refresh` quando o Windows troca de modo ou de tema de
  contraste (SPI_GETHIGHCONTRAST liga o alto contraste sozinho, como o "Aumentar contraste" do Mac).
- `contrast.zig`: as regras de leitura do HighContrast.swift do Mac: `readable` (10 metades rumo ao
  branco ou preto), `textOnTop`, `textOnTabActive` (o texto do tema a 4,5:1, senão preto ou branco),
  `withAccent` (aba ativa = mix(chrome, destaque, 0,22)) e `withHighContrast` (texto 7:1 contra
  panel, chrome e field, borda e destaque 3:1, aba ativa a 0,45, texto do terminal 7:1).
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
  Os de `import.zig`, `file.zig`, `catalog.zig` e `contrast.zig` só usam std e strings, e rodam
  também no Mac com zig test, dando o módulo strings (--dep strings -Mroot=arquivo
  -Mstrings=../../shared/strings/strings.zig).

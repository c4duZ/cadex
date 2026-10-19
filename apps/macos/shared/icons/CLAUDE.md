# icons (compartilhado do app)

## O que eu quero
- Os ícones de todo o app num lugar só: Phosphor, peso regular, pela fonte de ícones.

## O que eu não quero
- SF Symbols ou ícone de outra família misturado na interface.
- Ícone desenhado por cada feature: todas usam `Icon.swift`.

## Como eu quero
- `Icon.swift`: um caso por ícone usado, com o código do glifo tirado do style.css do pacote
  @phosphor-icons/web 2.1.2; `image(size:)` dá uma imagem modelo que o botão pinta. Ver
  `../../../../docs/adr/0008-phosphor-icons.md`.
- `Resources/Phosphor-Regular.ttf` é a fonte desse mesmo pacote, inteira; a licença está ao lado e
  no `NOTICE`. Ícone novo: achar o nome em phosphoricons.com, pegar o código no style.css da mesma
  versão e acrescentar um caso.
- `FileIcons.swift`: o ícone de um arquivo ou pasta, usado pela árvore do explorer e pelas abas.
  Primeiro o desenho do Material Icon Theme (`Resources/FileIcons`, PDFs gerados por
  `../../../../tools/icons/build_file_icons.py`, ver `../../../../docs/adr/0011-material-file-icons.md`);
  sem ele, o glifo Phosphor pela extensão, com a cor da tabela do CodeEdit (MIT, no NOTICE).

## Como validar
- `make macos-test` passa: todo caso tem glifo na fonte.

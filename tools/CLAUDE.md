# tools — verificações do repositório

## O que eu quero
- Checagens que transformam regras do repositório em falha de verdade.
- Geradores de dados embutidos no app, com as fontes deles, para a conversão poder ser refeita.

## O que eu não quero
- Script avulso esquecido aqui: script de uso único é apagado depois de rodar.

## Como eu quero
- Python 3 da biblioteca padrão, sem dependências. Cada checagem roda pelo Makefile.
- `themes/build_catalog.py`: gera o catálogo de temas do app a partir dos temas do tweakcn (commit
  fixado no script; o arquivo de entrada é passado na linha de comando) e de
  `themes/official-palettes.json` (paletas oficiais, cada cor com a fonte). Cortes de temas
  parecidos e o padrão ficam no script; descrições em `themes/descriptions.json`; licenças em
  `themes/licenses/` e no `NOTICE`.
- `icons/build_file_icons.py`: gera os ícones de arquivo e pasta do app a partir do Material Icon
  Theme (commit fixado no script; o checkout é passado na linha de comando), com
  `icons/svg_to_pdf.swift` convertendo para PDF. A lista do que entra fica no script
  (`docs/adr/0011-material-file-icons.md`).

## Como validar
- `make manifests` passa.

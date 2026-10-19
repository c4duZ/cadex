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

## Como validar
- `make manifests` passa.

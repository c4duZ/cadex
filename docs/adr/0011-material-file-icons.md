# 0011 — Ícones de arquivo e pasta do Material Icon Theme

Data: 2026-10-19 · Status: aceita (exceção ao 0008 só para tipos de arquivo)

## Contexto
A árvore do explorer e as abas mostravam cada arquivo com um glifo do Phosphor colorido por tipo. O
dono sentiu falta dos desenhos que reconhece do VS Code: a baleia do Docker, o logo do Git, do
Python, do Rust, a licença, e pastas com desenho próprio (`src`, `tests`, `docs`). O Phosphor não
tem nada disso: tem alguns arquivos por linguagem, nenhum logo de linguagem e nenhuma pasta por
nome. O pacote mais usado do VS Code para isso é o Material Icon Theme (licença MIT, 906 ícones).

## Decisão
- Arquivos e pastas que o Material Icon Theme conhece usam o desenho dele, nas cores dele; o resto
  continua no Phosphor (pastas na cor do tema, arquivos na cor do tipo). A interface (botões, barra
  de título, painéis) segue só Phosphor, como manda o 0008.
- Entra uma seleção dos ícones (155, os que uma árvore de desenvolvimento mostra), não o pacote
  inteiro. `tools/icons/build_file_icons.py` lê os mapas de nomes do pacote num commit fixado,
  copia a seleção e escreve `map.json` em `apps/macos/shared/icons/Resources/FileIcons`.
- Os SVGs viram PDF vetorial na geração (`tools/icons/svg_to_pdf.swift`, com o AppKit da máquina
  que gera): o app roda no macOS 13, que não lê SVG.

## Consequências
- Cerca de 0,9 MB a mais no app (os PDFs são maiores que os SVGs; ainda 2% do app).
- Ícone novo: acrescentar o nome à lista do gerador e rodá-lo de novo, nunca editar o JSON à mão.
- A licença do pacote está em `apps/macos/shared/icons/Resources/LICENSE-MaterialIconTheme.txt` e
  no `NOTICE`.
- No Windows (2026-10-20), a mesma seleção e o mesmo map.json, como PNG de 32 e 64 px desenhado
  pelo Direct2D (`tools/icons/windows_file_icons.py`, cerca de 360 KB no exe): o SVG do Direct2D
  (ID2D1DeviceContext5) só tem declaração em C++ nos headers do mingw, e a tabela dele à mão seria
  longa demais para acertar sem rodar. Explorer, abas e as buscas de arquivo usam os desenhos.

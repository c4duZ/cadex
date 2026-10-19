# media-preview

## Para que serve
Ver imagens, vídeos, áudios e PDFs do projeto numa aba, sem sair do Cadex, com o que o macOS já
sabe mostrar.

## Comportamento
- O tipo vem do conteúdo e da extensão: imagem (PNG, JPEG, GIF, WebP, HEIC, TIFF, BMP, ICO, SVG),
  vídeo (MP4, MOV, M4V, WebM quando o sistema toca), áudio (MP3, WAV, AAC, M4A, FLAC, AIFF), PDF.
  Outros arquivos que não são texto abrem pelo Quick Look, se ele souber mostrar.
- **Imagem:** centralizada, ajustada à aba quando maior que ela; ⌘+ e ⌘− dão zoom, ⌘0 volta a
  ajustar, ⌘1 mostra no tamanho real. Fundo xadrez discreto para transparência. Na parte de baixo,
  dimensões e tamanho do arquivo. GIF anima.
- **Vídeo e áudio:** controles do sistema (tocar, pausar, barra de tempo, volume, tela cheia no
  vídeo). Não começa a tocar sozinho.
- **PDF:** páginas roláveis, miniaturas opcionais na lateral, zoom e ⌘F para buscar no texto.
- O arquivo mudou no disco: a aba recarrega.

## Estados
- **Carregando:** o nome do arquivo e um indicador, para arquivos grandes.
- **Erro:** formato que o sistema não abre: "Não é possível mostrar este arquivo" com "Abrir no app
  padrão".

## Casos de borda
- Imagem de 20 000 × 20 000 -> abre reduzida, sem travar.
- Vídeo sem codec no sistema -> mensagem de erro, não tela preta.
- PDF protegido por senha -> pede a senha.

## Critérios de aceite
- [ ] O visualizador é escolhido pelo tipo do arquivo (imagem, vídeo, áudio, PDF, Quick Look, texto).
- [ ] `docs/cadex-icon.png` abre ajustado à aba, com zoom.
- [ ] Um PDF abre com busca.
- [ ] Um vídeo abre com os controles do sistema, parado.

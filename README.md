# Cadex

Um workspace de desenvolvimento centrado no terminal, nativo e leve.

Terminal, editor de código, explorador de arquivos, controle de versão com grafo do git e previews
(web, Markdown, imagem, vídeo, áudio e PDF), num app nativo para cada sistema. Sem telemetria, sem
conta, sem IA embutida: rode os seus agentes de código numa aba de terminal.

> **Status:** início do projeto. Nenhuma feature implementada ainda. O plano está no atlas do
> [`CLAUDE.md`](CLAUDE.md) e as decisões em [`docs/adr/`](docs/adr/).

## Arquitetura

```
                    ┌──────────────────────────────────────┐
                    │          Núcleo (Zig, API C)         │
                    │                                      │
                    │  terminal ── libghostty-vt           │
                    │  explorer · search · source-control  │
                    │  git-history · language-server       │
                    │  command-history · workspace         │
                    └──────────────────▲───────────────────┘
                                       │ API C
               ┌───────────────────────┴───────────────────────┐
               │                                               │
  ┌────────────┴────────────┐                    ┌─────────────┴────────────┐
  │   App macOS (Swift)     │                    │   App Windows            │
  │   AppKit · Metal        │                    │   (reservado)            │
  │   PDFKit · AVKit ·      │                    │                          │
  │   ImageIO · Quick Look  │                    │                          │
  └─────────────────────────┘                    └──────────────────────────┘
```

- **Núcleo:** toda a lógica que não depende de plataforma, escrita uma vez em Zig. O modelo do
  terminal é a [libghostty-vt](https://github.com/ghostty-org/ghostty).
- **App:** uma interface nativa e fina por sistema. Desenha, recebe entrada e chama o núcleo.
  Previews de mídia usam os frameworks do próprio sistema, sem peso extra.

O porquê de cada escolha está nos ADRs:
[macOS primeiro e app nativo](docs/adr/0001-macos-first-native-app.md) ·
[núcleo em Zig](docs/adr/0002-zig-core-with-c-api.md) ·
[libghostty-vt](docs/adr/0003-libghostty-vt-terminal-model.md) ·
[reescrita do zero](docs/adr/0004-clean-rewrite.md).

## Organização do repositório

```
core/             núcleo em Zig
  shared/         o que 2+ features do núcleo usam
  features/<x>/   uma pasta por feature, com CLAUDE.md e testes
apps/macos/       app Swift
  shared/         o que 2+ features do app usam
  features/<x>/   uma pasta por feature, mesmos nomes do núcleo
apps/windows/     reservado
docs/             vocabulário, decisões (adr/) e spec de comportamento (spec/)
tools/            verificações do repositório
```

Cada feature tem um `CLAUDE.md` curto com a responsabilidade, os pontos de entrada, as regras e como
testar. O repositório segue um método de organização para trabalho com agentes de IA: estrutura por
feature, manifestos curtos por pasta e verificação executável.

## Desenvolvimento

```bash
make check     # manifestos + testes do núcleo + testes do app
```

Pré-requisitos (quando houver código): macOS 13+, Xcode e Swift 6, Zig.

## Licença

[MIT](LICENSE), © 2026 Carlos Teixeira. Componentes de terceiros estão listados em [`NOTICE`](NOTICE).

O Cadex recria funcionalidades do [Terax](https://github.com/crynta/terax-ai) com código próprio,
escrito do zero (ver [ADR 0004](docs/adr/0004-clean-rewrite.md)).

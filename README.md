<p align="center">
  <img src="docs/images/icon.png" width="128" alt="Ícone do Cadex">
</p>

<h1 align="center">Cadex</h1>

<p align="center">
  Um workspace de desenvolvimento centrado no terminal, nativo e leve.<br>
  Terminal, editor de código, explorador de arquivos, git com grafo e previews (web, Markdown, imagem,
  vídeo, áudio e PDF) numa janela só. <b>Sem telemetria, sem conta, sem IA embutida:</b> rode os seus
  agentes de código numa aba de terminal.
</p>

<p align="center">
  <a href="https://github.com/c4duZ/cadex/releases/latest/download/Cadex.dmg"><img src="https://img.shields.io/badge/Baixar%20para%20Mac-macOS%2013%2B%20%C2%B7%20Intel%20e%20Apple%20Silicon-C06A2B?style=for-the-badge&logo=apple&logoColor=F2F2F2&labelColor=1E1E1E" alt="Baixar o Cadex para Mac" height="44"></a>
</p>

<p align="center">
  <sub>Grátis e de código aberto (MIT) · 7,6 MB · <a href="#instalar-no-mac">como instalar</a> · <a href="#pelo-terminal">instalar com um comando</a></sub>
</p>

---

## O que é

O Cadex junta num app nativo do macOS o que um dia de trabalho com agentes de código pede: o terminal
onde eles rodam, e em volta dele os arquivos, o código, o git e os previews, tudo alcançável pelo ⌘K.

- **Terminal** rápido e nítido (modelo da [libghostty](https://github.com/ghostty-org/ghostty),
  desenho em Metal), com abas, divisões, busca, links e colagem de imagens.
- **Documentos ao lado do terminal:** código, Markdown, mídia, diffs, histórico e previews abrem
  num painel da mesma aba (ou em aba própria, se preferir), divididos como terminais.
- **Spaces:** grupos de abas com nome, que voltam como estavam ao reabrir o app.
- **Explorador e busca** de arquivos por nome e por conteúdo, respeitando o `.gitignore`.
- **Editor de código** com destaque de sintaxe (tree-sitter), números de linha e dobras.
- **Markdown** renderizado, com links entre notas, links quebrados e quem aponta pra cá.
- **Git:** mudanças, stage, commit, push e pull, diff lado a lado e o grafo do histórico.
- **Previews:** servidores locais e páginas web, imagem, vídeo, áudio e PDF.
- **Temas:** 46 embutidos, imagem de fundo e vibrância.

## Instalar no Mac

<table>
  <tr>
    <td align="center" width="33%"><h3>1</h3><b>Baixe</b></td>
    <td align="center" width="33%"><h3>2</h3><b>Arraste para Aplicativos</b></td>
    <td align="center" width="33%"><h3>3</h3><b>Abra</b></td>
  </tr>
  <tr>
    <td valign="top">Clique em <a href="https://github.com/c4duZ/cadex/releases/latest/download/Cadex.dmg"><b>Baixar para Mac</b></a>. Vem sempre a versão mais recente.</td>
    <td valign="top">Abra o <code>Cadex.dmg</code> e arraste o ícone do Cadex para a pasta <b>Aplicativos</b>.</td>
    <td valign="top">Na primeira vez, o macOS avisa que não pode verificar o app: vá em <b>Ajustes do Sistema → Privacidade e Segurança</b> e clique em <b>Abrir Mesmo Assim</b>. Depois disso ele abre direto.</td>
  </tr>
</table>

Requisitos: macOS 13 ou superior, Intel ou Apple Silicon. Tudo o que o Cadex usa vem dentro do app: não
precisa instalar Xcode, Homebrew nem nada antes, e funciona offline.

### Pelo terminal

Um comando baixa a última versão, confere o checksum e coloca o Cadex em Aplicativos, sem pedir
senha e sem o aviso da primeira abertura:

```bash
curl -fsSL https://github.com/c4duZ/cadex/releases/latest/download/install.sh | sh
```

O script é curto e dá para ler antes de rodar: [`install.sh`](apps/macos/packaging/install.sh). Rodar
de novo atualiza para a versão mais recente.

<details>
<summary><b>Problemas na instalação?</b></summary>

- **O macOS não deixa abrir na primeira vez:** o Cadex ainda não é notarizado pela Apple. Vá em Ajustes do Sistema → Privacidade e Segurança → **Abrir Mesmo Assim**, ou rode `xattr -dr com.apple.quarantine /Applications/Cadex.app`.
- **O comando instalou em `~/Applications`:** a pasta Aplicativos do sistema não aceitou a cópia sem senha; o Cadex funciona igual de lá.
- **O botão de baixar dá 404:** enquanto o repositório for privado, os downloads só funcionam para quem tem acesso a ele e está logado no GitHub.
- **Versões anteriores:** na [página de releases](https://github.com/c4duZ/cadex/releases).

</details>

## Atalhos

Toda ação do Cadex é um comando: o **⌘K** acha e roda qualquer uma, e os atalhos podem ser trocados
nas configurações (⌘,).

| Ação | Atalho |
|---|---|
| Paleta de comandos | `⌘K` |
| Nova aba / fechar painel | `⌘T` / `⌘W` |
| Dividir à direita / para baixo | `⌘D` / `⌘⇧D` |
| Ir para a aba 1…9 | `⌘1…9` |
| Abrir arquivo por nome / buscar no conteúdo | `⌘P` / `⌘⇧F` |
| Abrir pasta | `⌘O` |
| Painel lateral / arquivos / git | `⌘B` / `⌘⇧E` / `⌘⇧G` |
| Histórico do git | `⌘⇧H` |
| Trocar de space / novo space | `⌘⇧S` / `⌃⌘N` |
| Buscar no terminal / limpar | `⌘F` / `⌘L` |

## Tamanho e memória

Métrica do projeto, medida a cada release ([ADR 0007](docs/adr/0007-one-step-install.md)).
Versão 0.1.0, 2026-10-19, num Mac com M4 e macOS 27:

| | Cadex | Terax v0.9.0 |
|---|---|---|
| download (DMG) | 7,5 MB | — |
| download (ZIP do instalador) | 7,1 MB | — |
| app instalado (universal: Apple Silicon e Intel) | 40 MB | 10,2 MB |
| memória com um terminal aberto (footprint) | 66 MB | — |

O app instalado é maior que o do Terax porque leva as duas arquiteturas e as 18 gramáticas do
tree-sitter compiladas dentro (as tabelas delas são 15 MB de cada fatia); o download comprimido fica
abaixo. O pico de memória ao abrir foi 111 MB.

## Arquitetura

```
                    ┌──────────────────────────────────────┐
                    │          Núcleo (Zig, API C)         │
                    │                                      │
                    │  terminal ── libghostty-vt           │
                    │  explorer · search · source-control  │
                    │  git-history · editor (tree-sitter)  │
                    │  markdown (índice de links)          │
                    │  workspace                           │
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

Requisitos: macOS 13+, as Command Line Tools (Swift 6; o Xcode completo não é preciso) e Zig 0.16.

```bash
make check     # manifestos + testes do núcleo + testes do app
make run       # compila e abre o app
make package   # gera dist/Cadex.app universal (Intel + Apple Silicon), assinado ad hoc
```

O identificador `io.github.c4duz.cadex` é fixo na assinatura para o macOS manter as permissões dadas
ao Cadex entre um build e outro.

### Publicar uma versão

```bash
# 1. Suba CFBundleShortVersionString (ex.: 0.2.0) e CFBundleVersion (inteiro, sempre maior)
#    em apps/macos/packaging/Info.plist
# 2. Gere e publique (requer: brew install create-dmg, e o gh logado na conta dona do repositório)
apps/macos/packaging/release.sh --publish "O que mudou nesta versão"
```

O script gera o `Cadex.dmg`, o `Cadex.zip` com o checksum e o `install.sh`, e cria a release
`vX.Y.Z`. Os arquivos sobem com nome fixo, sem a versão, para o botão de download e o comando de
instalação do topo sempre pegarem a última. Sem `--publish`, ele só gera os arquivos em `dist/`.

## Licença

[MIT](LICENSE), © 2026 Carlos Teixeira. Componentes de terceiros estão listados em [`NOTICE`](NOTICE).

O Cadex recria funcionalidades do [Terax](https://github.com/crynta/terax-ai) com código próprio,
escrito do zero (ver [ADR 0004](docs/adr/0004-clean-rewrite.md)).

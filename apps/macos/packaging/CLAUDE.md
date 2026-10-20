# packaging (app macOS)

Receita de empacotamento reaproveitada do BKDict (projeto vizinho, ../BKDict: build.sh e
scripts/release.sh), que já distribui um app Swift sem Xcode completo e sem conta Apple Developer.

- `build.sh` (ou `make package`): monta dist/Cadex.app na raiz do repositório, universal, com o
  `Info.plist` desta pasta (bundle id io.github.c4duz.cadex, versão, categoria, pastas e arquivos
  soltos no ícone do Dock; http liberado só no conteúdo web, para o preview abrir sites sem https;
  NSAppleEventsUsageDescription, sem a qual o macOS recusava em silêncio o AppleScript de quem roda
  num terminal do Cadex: o create-dmg da release falhou assim em 2026-10-20).
  Leva 1 min e meio.
- `release.sh`: build, Cadex.zip com o Cadex.zip.sha256, latest.json (para o app se atualizar,
  assinado por `sign-update.swift` com a chave do Keychain), Cadex.dmg (create-dmg com o
  `dmg-background.tiff`, gerado por `dmg-background.swift`) e o install.sh em dist/. Só publica com
  `--publish "notas"` (gh release create com nomes sem versão). `CADEX_DMG_PLAIN=1` faz o DMG sem
  mexer no Finder (sem fundo nem posições), para testar com alguém usando a máquina.
  `CADEX_WINDOWS=1` também monta e sobe os arquivos do Windows (`../../windows/packaging/CLAUDE.md`).
- `install.sh`: o instalador por comando (sh, sem sudo): baixa o ZIP e o checksum da última
  release, confere, põe em /Applications ou ~/Applications e tira a quarentena só do Cadex.
  `CADEX_DOWNLOAD` (URL ou pasta) e `CADEX_INSTALL_DIR` trocam a origem e o destino nos testes.

## O que eu quero
- Um `.app` universal (Apple Silicon + Intel) gerado só com as Command Line Tools.
- Um DMG de "arrastar para Aplicativos" com fundo e ícone próprios, e um ZIP do mesmo app.
- Release publicada no GitHub com DMG, ZIP e o latest.json assinado que o app lê para se atualizar.
- O instalador por comando do ADR 0007 baixando o mesmo ZIP da release.

## O que eu não quero
- Depender do Xcode completo para gerar a release (ver `../../../docs/adr/0007-one-step-install.md`).
- Assinatura ad hoc padrão: ela usa o cdhash como identidade, e o macOS esquece as permissões
  (Acessibilidade, Microfone, Arquivos) a cada build novo.
- Prometer que o app abre sem aviso: sem Developer ID e notarização, a primeira abertura pelo DMG
  pede "Abrir Mesmo Assim". O README explica isso, como o do BKDict faz.

## Como eu quero
- Universal sem xcbuild: compilar cada arquitetura separada e juntar com lipo. O
  `swift build --arch arm64 --arch x86_64` exige o Xcode completo.
  - `swift build -c release --triple arm64-apple-macosx13.0` e o mesmo com `x86_64-...`;
  - `lipo -create <bin arm64> <bin x86_64> -output Cadex.app/Contents/MacOS/Cadex`;
  - o núcleo Zig também nas duas arquiteturas (zig build -Dtarget=x86_64-macos.13.0 e
    aarch64-macos.13.0), juntando as duas libcadex.a com lipo antes do link.
- Montar o bundle à mão: Info.plist, ícone (`sips` gera os tamanhos a partir do
  `docs/cadex-icon.png` e `iconutil -c icns` monta o .icns), LICENSE e NOTICE em Resources.
- Recursos do código (a fonte Phosphor, o catálogo de temas) vão soltos em Contents/Resources e o
  código procura primeiro no Bundle.main: o Bundle.module do SwiftPM procura na raiz do .app, que a
  assinatura não aceita, e depois num caminho da máquina que compilou.
- O núcleo sai nas duas arquiteturas e as duas libcadex.a viram uma só, gorda, em
  core/zig-out/lib (onde o Package.swift liga); cada swift build pega a fatia dele. Os executáveis
  de release são apagados antes, porque o swift build não religa quando só a biblioteca mudou.
- `strip -x` antes de assinar (3 MB a menos).
- Assinar de dentro para fora, ad hoc, fixando a identidade no bundle id:
  `codesign --force --sign - -r='designated => identifier "<bundle id>"' Cadex.app`
  (frameworks antes, com `codesign --force --deep --sign -`).
- ZIP com `ditto -c -k --keepParent Cadex.app`, que preserva atributos e assinatura.
- DMG com `create-dmg` (brew): volname, volicon, background, tamanho da janela, posição do ícone do
  app e do atalho de Aplicativos. Ele controla o Finder por AppleScript, então roda numa sessão
  logada (não em CI headless). O fundo do BKDict é gerado por um script Swift, com as posições dos
  ícones combinando com as do build.
- Publicar com `gh release create` usando nomes sem versão (Cadex.dmg) para os links
  `releases/latest/download/...` do README sempre baixarem a última.
- Atualização dentro do app sem Sparkle (`../../../docs/adr/0016-in-app-updates.md`): o
  `sign-update.swift` assina o Cadex.zip com Ed25519 e escreve o latest.json (versão, notas, ZIP
  desta versão, SHA-256, assinatura). A chave privada fica no Keychain, item
  `cadex-update-signing` (conta `cadex`), com uma cópia em `CADEX_UPDATE_KEY` no .env da raiz
  (fora do git; o release.sh usa se o Keychain não tiver), e chega ao script pela entrada padrão; a pública está em
  `../features/updates/UpdateVerifier.swift`. Sem a chave, `release.sh --publish` recusa. Chave
  nova: `swift sign-update.swift keygen`, a privada no Keychain com `security
  add-generic-password -s cadex-update-signing -a cadex -w <privada>`, a pública no código; quem
  estiver numa versão antiga atualiza uma vez pelo install.sh.

## Como validar
- `codesign -dv --verbose=2 Cadex.app` mostra `Identifier=` com o bundle id e `Signature=adhoc`.
- `lipo -archs Cadex.app/Contents/MacOS/Cadex` lista `x86_64 arm64`.
- O app abre num Mac Intel e num Apple Silicon, e as permissões dadas continuam depois de um build novo.
  Sem Mac Intel à mão: `arch -x86_64 dist/Cadex.app/Contents/MacOS/Cadex` roda a fatia Intel no
  Rosetta (conferido em 2026-10-19; falta um Mac Intel de verdade).
- `spctl -a -vv Cadex.app` dá `rejected` enquanto não houver notarização: esperado, não é bug.
- O latest.json de dist/ confere com a chave pública do app; com ele, `CADEX_UPDATE_FEED=dist/latest.json`
  numa cópia mais velha do app mostra o botão de atualização (`../features/updates/CLAUDE.md`).
- `CADEX_DOWNLOAD=dist CADEX_INSTALL_DIR=<pasta de teste> sh install.sh` instala e a assinatura
  confere; com o ZIP alterado, recusa sem instalar nada. O DMG montado com `hdiutil attach
  -nobrowse` tem o Cadex.app assinado e o atalho para Aplicativos.

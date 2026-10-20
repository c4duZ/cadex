# updates (app macOS)

## O que eu quero
- Atualizar o Cadex com um clique: procura versão nova ao abrir e a cada 6 horas, mostra um botão
  na barra de título quando há, e "Instalar e reabrir" baixa, confere, troca o app e reabre.
  Spec: `../../../../docs/spec/updates.md`; decisão: `../../../../docs/adr/0016-in-app-updates.md`.

## O que eu não quero
- Sparkle ou outra dependência: `URLSession`, CryptoKit, `ditto` e `FileManager` bastam.
- Tocar no app instalado antes de conferir o SHA-256 e a assinatura Ed25519 do ZIP.
- Mensagem por falha da procura automática (sem internet não é motivo para avisar).

## Como eu quero
- `UpdateController.swift`: a porta de entrada, uma para o app inteiro. Estados idle, checking,
  upToDate, available, downloading, installed e failed; `onChange` avisa a barra de título.
  `CADEX_UPDATE_FEED` troca o latest.json (URL ou caminho) para testar uma release antes de
  publicar. Fora do pacote .app (`make run`) não procura e os comandos ficam indisponíveis.
- `UpdateRelease.swift`: o latest.json e a comparação de versões.
- `UpdateVerifier.swift`: SHA-256 e assinatura, com a chave pública da release.
- `UpdateDownload.swift` e `UpdateInstaller.swift`: baixar com progresso, abrir com ditto,
  conferir bundle id, versão e assinatura de código, e trocar com `replaceItemAt`.
- `UpdatePanel.swift`: a janela de "Procurar atualizações"; os botões rodam comandos pelo id
  (`runCommand`).
- `UpdateCommands.swift`: app.check-for-updates e app.install-update (só no Mac por enquanto:
  `MAC_ONLY` em `../../../../tools/check_command_parity.py`).
- A release publica o latest.json assinado: `../../packaging/sign-update.swift`, chamado pelo
  `../../packaging/release.sh`.

## Como validar
- `make macos-test` passa: versões, latest.json, assinatura certa e errada, instalação sobre um app
  falso, recusa de ZIP adulterado.
- `CADEX_UPDATE_FEED=<latest.json de teste> dist/Cadex.app/Contents/MacOS/Cadex` mostra o botão e
  instala.

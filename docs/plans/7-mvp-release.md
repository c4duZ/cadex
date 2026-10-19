# Plano 7 — Fechar o MVP: spaces, empacotamento e semana de uso

Depende de: planos 1 a 6 · Features: spaces (app), empacotamento (`apps/macos/packaging/CLAUDE.md`)
· Decisões: `docs/adr/0007-one-step-install.md` · Spec a escrever: spaces.

## O que eu quero
- **Spaces:** grupos de abas com nome, alternáveis pela paleta e por atalho; ao reabrir o app, cada
  space volta com as abas, as divisões, a pasta de cada painel e os arquivos abertos (o conteúdo
  antigo do terminal não volta: cada painel começa um shell novo). Fechar o app de surpresa não perde
  o layout.
- **App de verdade:** Cadex.app universal (Apple Silicon e Intel), macOS 13+, ícone a partir de
  `docs/cadex-icon.png`, assinatura ad hoc presa ao bundle id, funcionando offline.
- **Instalação em um passo** (ADR 0007): `curl -fsSL <url>/install.sh | sh` baixa o ZIP da última
  release, coloca em Aplicativos e termina, sem sudo; DMG de arrastar para Aplicativos como
  alternativa, com a explicação do "Abrir mesmo assim" na página de download.
- **Release no GitHub** com Cadex.dmg, Cadex.zip e install.sh, nomes sem versão para o link
  releases/latest/download/ sempre pegar a última.
- **Semana de uso:** o dono usa o Cadex no lugar do Terax por uma semana; o que faltar vira plano.

## O que eu não quero
- Depender do Xcode completo para gerar a release, ou de conta Apple Developer (ADR 0007).
- Assinatura ad hoc padrão (o macOS esquece as permissões a cada build): fixar a identidade no
  bundle id, como descreve `apps/macos/packaging/CLAUDE.md`.
- Script de instalação com sudo, ou que baixe algo além do app.
- Atualização automática dentro do MVP: decisão própria depois (Sparkle é a opção registrada).

## Como eu quero
**Onde estamos.** O app roda por `make run` como executável solto (`apps/macos/app/main.swift` liga
a política de app regular). Não há .app, ícone, Info.plist nem scripts de release. A receita
completa, testada no projeto vizinho BKDict, está em `apps/macos/packaging/CLAUDE.md`.

**Fases:**
- **A. Spaces:** modelo de space (nome, abas, árvore de painéis, pastas, arquivos abertos) salvo em
  JSON em Application Support/Cadex a cada mudança (gravação atômica, com atraso curto para agrupar);
  restaurar ao abrir; comandos novo/renomear/trocar/fechar space.
- **B. Build universal:** script em apps/macos/packaging (build.sh) que compila o núcleo nas duas
  arquiteturas (`zig build -Doptimize=ReleaseFast -Dtarget=aarch64-macos.13.0` e x86_64), junta as
  duas libcadex.a com lipo, compila o Swift por triple e junta os executáveis com lipo; monta o
  bundle (Info.plist com bundle id, versão, categoria; ícone com sips + iconutil; NOTICE e LICENSE
  em Resources); assina ad hoc com o requisito designado.
- **C. DMG, ZIP e instalador:** create-dmg com fundo e posições; ZIP com ditto; install.sh curto e
  legível (baixa, confere, move para /Applications ou ~/Applications se não tiver permissão, remove
  quarentena só do próprio app); release.sh com `gh release create`.
- **D. Medir:** tamanho do DMG, do app e memória com um terminal aberto, registrados no README (é
  métrica do projeto, ADR 0007), comparados com o Terax (10,2 MB de app no upstream v0.9.0).
- **E. Semana de uso:** lista do que faltou ou incomodou, cada item vira spec e plano novo.

## Como validar
- `make check` passa ao fim de cada fase.
- Testes: space salvo e restaurado igual (abas, divisões, pastas); arquivo de spaces corrompido não
  impede o app de abrir (volta ao padrão e guarda o arquivo ruim ao lado).
- Pacote: `lipo -archs` lista x86_64 e arm64; `codesign -dv` mostra o bundle id e assinatura adhoc;
  `spctl -a -vv` dá rejected (esperado sem notarização); app abre num Mac Intel e num Apple Silicon.
- Instalação: num usuário limpo, o comando do install.sh deixa o Cadex em Aplicativos e ele abre;
  o DMG instala arrastando.
- Fim do MVP: critérios de aceite das specs marcados, semana de uso concluída, status na tabela de
  `docs/plans/README.md`.

## Andamento (2026-10-19)
Fases A a D feitas, cada uma num commit; falta a E (semana de uso), que é do dono.

- **A. Spaces:** salvos em Application Support/Cadex/spaces.json meio segundo depois de cada mudança
  e ao sair; conferido no app (novo space, dividir, histórico aberto, sair pelo menu, reabrir com as
  abas, a divisão, o foco e o space ativo; abrir sem pasta devolve a pasta do workspace). Os
  documentos restaurados têm a pasta autorizada de novo (o histórico de um repositório fora do
  workspace falhava).
- **B. Build universal:** `make package` gera o app em 1 min e meio; lipo, codesign e spctl dão o
  esperado. A fatia Intel rodou pelo Rosetta (`arch -x86_64`). Achado no caminho: o terminal criado
  antes de entrar na janela (o primeiro de um space) ficava em branco; agora redesenha ao entrar.
- **C. DMG, ZIP e instalador:** `release.sh` gera tudo em dist/ e só publica com `--publish`. O
  install.sh instalou numa pasta de teste e recusou um ZIP alterado. O DMG foi testado sem o passo
  do Finder (CADEX_DMG_PLAIN=1), para não abrir janelas na frente do dono.
- **D. Medidas:** no README (DMG 7,5 MB, app 40 MB, 66 MB de memória com um terminal).

Release v0.1.0 publicada em 2026-10-19 (https://github.com/c4duZ/cadex/releases/tag/v0.1.0), com o
DMG de fundo e posições; o comando do README instalou a versão publicada numa pasta de teste, com a
assinatura e as duas arquiteturas conferidas. Falta, com o dono: instalar num usuário limpo, abrir num Mac Intel de verdade, trocar de space pela paleta (⇧⌘S e escolher) e a
semana de uso. Decisões tomadas sem o dono, para confirmar: bundle id io.github.c4duz.cadex (mudar
depois faz o macOS esquecer as permissões), atalhos ⇧⌘S, ⌃⌘N e ⌃⌘←/→ para spaces, e o checksum
SHA-256 publicado junto do ZIP.

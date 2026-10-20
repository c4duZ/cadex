# Plano 13 — Spaces, painéis com documentos e release do Windows

Depende de: plano 12 · Features: spaces, tabs (painéis com documentos), empacotamento do Windows ·
Decisões: `docs/adr/0007-one-step-install.md`, `docs/adr/0012-windows-zig-win32-d3d11.md`.

## O que eu quero
- Spaces salvos e restaurados no Windows com o mesmo spaces.json do Mac (pastas convertidas quando o
  caminho não existir na máquina) e documentos em painéis ao lado do terminal, como no plano 8.
- **Instalação em um passo** (ADR 0007): `irm <url>/install.ps1 | iex` no PowerShell baixa o ZIP da
  última release, instala em %LOCALAPPDATA%\Programs\Cadex, cria o atalho no Menu Iniciar e a entrada
  de desinstalar, sem administrador. ZIP portátil como alternativa.
- Release no GitHub com Cadex-windows-x64.zip, Cadex-windows-arm64.zip e install.ps1, nomes sem
  versão para o releases/latest/download/ pegar sempre a última, na mesma release do Mac.
- O dono usa o Cadex no Windows uma semana; o que faltar vira plano.

## O que eu não quero
- MSI, MSIX ou instalador de terceiros (Inno, NSIS) no começo: o ZIP e o script bastam.
- Pedir administrador, ou instalar algo além do app.
- Atualização automática agora: decisão própria depois.

## Como eu quero
**Fases:**
- **A. Spaces e documentos em painéis.** Mesmo modelo e mesmo arquivo do Mac, em %APPDATA%\Cadex.
  *Spaces feitos em 2026-10-20 (`apps/windows/features/spaces/spaces.zig`); os documentos chegam
  com os visualizadores do plano 12.*
- **B. Pacote.** Script em apps/windows/packaging: build nas duas arquiteturas (núcleo ReleaseFast,
  app ReleaseSmall), ícone .ico a partir de `docs/cadex-icon.png`, recurso de versão no exe, NOTICE e
  LICENSE no ZIP. *Feito em 2026-10-20 (`apps/windows/packaging/build.sh`): ZIPs de 3 MB.*
- **C. Instalador e release.** install.ps1 curto e legível; release.sh passa a subir os arquivos do
  Windows junto com os do Mac. A página de download explica o aviso do SmartScreen (sem assinatura).
  *Escrito em 2026-10-20 (`apps/windows/packaging/install.ps1`), ainda não rodado no Windows; o
  release.sh só leva o Windows com CADEX_WINDOWS=1, e a seção do README entra quando ele rodar.*
- **D. Medir.** Tamanho do ZIP, do exe e memória com um terminal, no README ao lado dos do Mac.
- **E. Semana de uso no Windows.**

## Como validar
- `make check` passa; testes do app Windows passam na VM.
- Numa VM limpa: o comando do install.ps1 deixa o Cadex no Menu Iniciar e ele abre; desinstalar
  pelas Configurações do Windows remove tudo.
- Fim do port: critérios de aceite das specs marcados também no Windows, status na tabela de
  `docs/plans/README.md`.

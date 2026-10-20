# packaging (app Windows)

## O que eu quero
- Dois ZIPs portáteis, Cadex-windows-x64.zip e Cadex-windows-arm64.zip, cada um com o Cadex.exe
  (ícone e versão embutidos), LICENSE e NOTICE, e o checksum ao lado.
- O instalador por comando do ADR 0007 (`../../../docs/adr/0007-one-step-install.md`), em
  PowerShell: `irm https://github.com/c4duZ/cadex/releases/latest/download/install.ps1 | iex`.
- Os arquivos do Windows na mesma release do Mac, com a mesma versão.

## O que eu não quero
- MSI, MSIX, Inno ou NSIS: o ZIP e o script bastam (plano 13).
- Pedir administrador, ou instalar algo além do app.
- Uma release do Mac levando o Windows antes de ele rodar numa máquina Windows: o release.sh do
  Mac (`../../macos/packaging/release.sh`) só sobe os arquivos com CADEX_WINDOWS=1.

## Como eu quero
- `build.sh` (ou `make windows-package`): núcleo ReleaseFast e app ReleaseSmall nas duas
  arquiteturas, com a versão do `../../macos/packaging/Info.plist` passada em -Dversion; ZIPs, os
  .sha256 e o install.ps1 em dist/ na raiz. Leva uns 40 s; cada ZIP tem uns 3 MB.
- O ícone: `../app/Cadex.ico`, gerado de `docs/cadex-icon.png` por
  `../../../tools/icons/windows_ico.py` (9 tamanhos, PNG dentro do ICO). O `../build.zig` escreve o
  Cadex.rc (ícone 1, que a janela carrega, e VERSIONINFO) e liga com addWin32ResourceFile.
- `install.ps1`:
  - escolhe a arquitetura por PROCESSOR_ARCHITEW6432 ou PROCESSOR_ARCHITECTURE;
  - baixa o ZIP e o checksum, confere e só então instala em %LOCALAPPDATA%\Programs\Cadex;
  - cria o atalho no Menu Iniciar e a entrada em Configurações → Apps (HKCU, desinstalar remove a
    pasta, o atalho e a entrada; os arquivos do usuário em %APPDATA%\Cadex ficam);
  - recusa atualizar com o Cadex aberto;
  - erro por throw, não exit: com `irm | iex` o exit fecha a janela do usuário.
  CADEX_DOWNLOAD (URL ou pasta) e CADEX_INSTALL_DIR trocam origem e destino nos testes, e com
  CADEX_INSTALL_DIR não há atalho nem entrada no registro.
- Sem assinatura de código: o SmartScreen avisa na primeira abertura do ZIP baixado pelo navegador
  ("Mais informações" → "Executar assim mesmo"). O install.ps1 tira a marca da internet só dos
  arquivos do Cadex. Quando a release do Windows sair, o README ganha a seção "Instalar no Windows"
  com o comando e esse aviso.

## Como validar
- `bash apps/windows/packaging/build.sh` gera os dois ZIPs e os checksums conferem
  (`shasum -a 256 -c` dentro de dist/).
- Na VM: `$env:CADEX_DOWNLOAD='<pasta com o dist>'; .\install.ps1` instala, o Cadex aparece no
  Menu Iniciar com o ícone e abre; Propriedades do exe mostram a versão; desinstalar pelas
  Configurações remove tudo; com o ZIP alterado, recusa sem instalar.

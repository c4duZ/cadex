# Plano 9 — Núcleo no Windows

Depende de: plano 8 (v1.0.0 no Mac) · Features: terminal, explorer, search, source-control,
git-history, workspace, editor, markdown (núcleo) · Decisões: `docs/adr/0012-windows-zig-win32-d3d11.md`,
`docs/adr/0009-regex-from-the-system.md` · Specs a mudar: workspace, search (sintaxe da regex).

## O que eu quero
- O mesmo `core/` compilando para Windows 11 x64 e arm64 a partir deste Mac, sem nenhuma feature a
  menos que no macOS, e a API C (`core/include/cadex.h`) igual nas duas plataformas.
- `zig build test` passando dentro de uma VM com Windows 11 ARM, com o alocador de teste ligado,
  disparado daqui por um comando só.
- Cada parte que hoje é POSIX ganha a versão Windows atrás da mesma função: PTY (ConPTY), processos
  (CreateProcessW), observação do disco (ReadDirectoryChangesW), regex, diretório atual do shell.
- Workspace no Windows: caminhos com letra de unidade e `\`, e o ambiente WSL (distros instaladas,
  shell e pastas dentro da distro), como descreve a spec.

## O que eu não quero
- `#ifdef` espalhado: a diferença de sistema fica num arquivo por plataforma dentro da feature
  (ex.: pty_posix.zig e pty_windows.zig), escolhido num ponto só pelo builtin.os.tag.
- Mudar a API C por causa do Windows. Se um tipo precisar mudar, muda nos dois apps no mesmo commit.
- Quebrar o macOS: `make check` continua passando a cada fase.
- Teste que só passa no Mac por depender de `/tmp`, `/bin/sh` ou permissões POSIX sem dizer.

## Como eu quero
**Onde estamos (2026-10-19).** `core/build.zig` liga o CoreServices e chama `xcrun` sempre. Com isso
contornado, `zig build -Dtarget=x86_64-windows-gnu` mostra que a libghostty-vt, o simdutf, o highway,
o tree-sitter e o md4c já compilam; os erros ficam em `core/features/terminal/pty.zig` (forkpty),
`core/shared/process.zig` (posix_spawn), `core/features/explorer/watch.zig` (FSEvents),
`core/shared/regex.zig` (TRE da Apple) e no uso de `AT_FDCWD`/funções da libc em
`core/features/explorer/listing.zig`, `core/features/explorer/operations.zig`,
`core/features/explorer/write.zig` e `core/features/search/walker.zig`.

**Fases:**
- **A. VM e laço de teste.** O dono instala o UTM e uma VM Windows 11 ARM com o OpenSSH Server
  ligado e o Git for Windows. Um script em tools (windows-vm.sh) copia um executável por `scp` e roda
  por `ssh`; `make windows-core-test` compila os testes do núcleo para aarch64-windows sem rodar,
  manda para a VM e mostra o resultado. Registrar a receita da VM em apps/windows/CLAUDE.md.
- **B. Build por sistema.** `core/build.zig` escolhe pelo alvo: frameworks e SDK só no macOS; no
  Windows, as bibliotecas do sistema necessárias (kernel32, advapi32, ...). Alvo padrão continua o
  Mac. `make windows-core` gera a libcadex.a para x86_64 e aarch64 (Windows 11, CPU base).
- **C. Arquivos e caminhos.** Listagem, operações de arquivo, escrita atômica e o walker da busca
  pela API de diretórios do std do Zig (que já fala Windows) em vez da libc. Caminhos na API C
  continuam UTF-8; no Windows aceitam `C:\`, `\\?\` e UNC (incluindo `\\wsl.localhost\`). Testes com
  nomes Unicode, maiúsculas e minúsculas (o NTFS não diferencia) e arquivos abertos por outro
  processo.
- **D. Processos.** `core/shared/process.zig` ganha a versão Windows: CreateProcessW com pipes, linha
  de comando com as aspas do Windows, ambiente em UTF-16, grupo de processos (Job Object) para o
  cancelamento matar a árvore toda. O git do source-control e do git-history passa por aqui; o
  binário vem do Git for Windows (git.exe no PATH ou o caminho padrão).
- **E. PTY com ConPTY.** CreatePseudoConsole, um fio de leitura por sessão, ResizePseudoConsole,
  fim da sessão por espera no processo. Shell padrão: PowerShell 7 se instalado, senão Windows
  PowerShell; cmd por configuração. Diretório atual do shell (que no Mac vem de proc_pidinfo) pela
  sequência OSC 7 que o shell manda, com a integração de shell do PowerShell registrada na spec.
- **F. Observação do disco.** ReadDirectoryChangesW recursivo, com o mesmo agrupamento e a mesma
  latência do FSEvents, entregando os mesmos eventos ao callback de `core/features/explorer/watch.zig`.
- **G. Regex.** Decidir em ADR (revisando o 0009) entre compilar a TRE (BSD, a mesma base da libc
  da Apple) para as duas plataformas, PCRE2 ou um motor próprio. Critério: a mesma sintaxe no Mac e
  no Windows. Aplicar atrás de `core/shared/regex.zig` sem mudar a API.
- **H. Workspace e WSL.** Distros por `wsl.exe -l -q` (saída em UTF-16), shell dentro da distro
  (`wsl.exe -d <distro> --cd <pasta>`), conversão de caminho Windows ↔ Linux, ambiente atual exposto
  na API para a status bar. Spec de workspace atualizada.

## Andamento (2026-10-19)
Fases B a G feitas, cada uma em commits pequenos: o núcleo inteiro compila e liga para Windows 11
x64 e arm64 (`make windows-core`), e os testes do Mac continuam passando. O script da VM
(`tools/windows-vm.sh`, `make windows-core-test`) está pronto, mas ainda não há VM: os testes
nunca rodaram no Windows. Falta: a VM (fase A, do dono), rodar e corrigir o que falhar lá, e a
fase H (WSL). Depois, pelo comportamento descrito na documentação pública do Terax: integração de
shell automática do PowerShell (OSC 7), pwsh → Windows PowerShell → cmd como shell padrão, pasta
avisada convertida para C:\x, e git procurado onde o Git for Windows instala.

## Como validar
- `make check` passa no Mac ao fim de cada fase.
- `make windows-core` gera as duas libcadex.a; `make windows-core-test` passa na VM sem vazamento.
- Testes novos: PTY abre o PowerShell, recebe `echo` e devolve; resize muda `$Host.UI.RawUI`; git
  status de um repo de teste igual ao do Mac; observação pega criar, renomear e apagar; regex dá o
  mesmo resultado nas duas plataformas para a mesma tabela de casos; uma distro WSL listada e um
  shell aberto nela (pula com aviso se a VM não tiver WSL).
- Status na tabela de `docs/plans/README.md`.

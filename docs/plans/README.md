# Planos: do fim do terminal ao MVP no Mac

Sete planos, um por entrega que o dono abre e usa. Cada plano é autocontido e dividido em fases que
cabem numa sessão. Escritos em 2026-10-19, quando o Cadex tinha o terminal funcionando numa janela
(shell num PTY, desenho em Metal, SF Mono nítido, teclado básico, edição estilo Mac com ⌥ e ⌘).

## O que eu quero
- Chegar ao MVP do Cadex no macOS: um app que substitui o Terax no dia a dia do dono, mais leve,
  com código próprio e licença MIT.
- Executar nesta ordem; cada plano começa com o anterior concluído:

| # | plano | entrega | status |
|---|---|---|---|
| 1 | `docs/plans/1-terminal.md` | terminal completo, no nível do Terax | feito; falta conferência manual |
| 2 | `docs/plans/2-tabs-splits-palette.md` | abas, divisões e paleta ⌘K | feito |
| 3 | `docs/plans/3-window-and-theme.md` | janela com a cara do Terax, tema, configurações | pendente |
| 4 | `docs/plans/4-files.md` | workspace, explorer e busca | pendente |
| 5 | `docs/plans/5-viewers.md` | código, Markdown, mídia e preview web | pendente |
| 6 | `docs/plans/6-git.md` | source control e grafo do git | pendente |
| 7 | `docs/plans/7-mvp-release.md` | spaces que restauram, empacotamento, semana de uso | pendente |

## O que eu não quero
- Executar plano sem ler antes o `CLAUDE.md` da raiz e o da feature que vai mexer.
- Código do Terax como referência (ADR 0004): a fonte é a spec em `docs/spec/`, a documentação
  pública do Terax e o que o dono descreve. Feature nova começa escrevendo a spec dela
  (`docs/spec/README.md` tem o modelo).
- Começar uma fase com a anterior pela metade, ou terminar uma fase sem commit.
- Inflar o MVP: o que não está nos planos entra depois, com plano próprio.

## Como eu quero
Começando uma sessão do zero:
1. Ler `CLAUDE.md` (raiz), este índice e o plano da vez. Os planos citam os arquivos que importam.
2. Ferramentas da máquina: Zig 0.16 em `~/.local/bin/zig` (a libghostty exige 0.16; não usar o do
   Homebrew), Swift 6 das Command Line Tools (sem Xcode), Rust não é usado no Cadex.
3. Comandos: `make check` (manifestos + testes do núcleo + testes do app), `make run` (abre o app),
   `make core` (só a biblioteca).
4. Ver o app de verdade: com o app aberto, o id da janela sai de um programinha Swift que lista
   janelas com CGWindowListCopyWindowInfo (dono "Cadex"), e `screencapture -x -o -l <id> arquivo.png`
   tira o print para conferir visualmente.
5. Conferir no app sem roubar o teclado do dono, que pode estar usando a máquina: acionar comandos
   pelos itens de menu do processo (`tell application "System Events" to tell process "Cadex" to
   click menu item "Dividir à direita" of menu "Painéis" of menu bar 1`) e capturar a janela com
   `screencapture -l`, que funciona com ela atrás. Abrir o app para teste com `CADEX_BACKGROUND=1`, que
   mostra a janela sem ativar o app nem tomar o foco. Tecla simulada vai para o app que estiver na
   frente: só usar depois de conferir que é o Cadex, logo antes de cada envio. Em 2026-10-19 teclas
   de teste caíram no Chrome do dono.

Ao fim de cada fase: `make check` passando, commit pequeno, `CLAUDE.md` das features tocadas
atualizado (status, pontos de entrada, regras), spec com os critérios marcados. Ao fim de cada plano:
marcar o status na tabela acima.

## Como validar
- `make check` passa ao fim de cada fase.
- O MVP está pronto quando todos os critérios de aceite das specs das features do atlas
  (`CLAUDE.md` da raiz) estão marcados e o dono usa o Cadex uma semana no lugar do Terax.

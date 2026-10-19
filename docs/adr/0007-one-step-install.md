# 0007 — Instalação em um passo

Data: 2026-10-19 · Status: aceita

## Contexto
O Cadex é para desenvolvedores que trabalham com agentes de IA, mas instalar tem que ser tão simples
quanto qualquer app comum do Mac. Zig, Xcode e Swift são ferramentas de compilação; quem usa o app
não pode precisar de nenhuma delas.

## Decisão
- A distribuição no macOS é um DMG: abrir, arrastar o Cadex para Aplicativos, abrir o app. Nenhum
  outro passo.
- Tudo o que o app usa vai dentro dele: o núcleo Zig, a libghostty-vt e o tree-sitter compilados no
  binário, recursos e licenças no bundle. Sem dependência instalada à parte, sem permissão de
  administrador, sem terminal.
- O app é assinado com Developer ID e notarizado pela Apple, para abrir sem o aviso de
  "desenvolvedor não verificado" do Gatekeeper.
- Binário universal (Apple Silicon e Intel), para ninguém precisar escolher a versão certa.
- Funciona offline desde a primeira abertura.

## Consequências
- Precisa de uma conta Apple Developer e do Xcode na máquina (ou no CI) que gera o DMG final. O
  desenvolvimento do dia a dia não precisa do Xcode.
- Dependência nova só entra se puder ir dentro do bundle; nada que exija instalação no sistema.
- O tamanho do DMG é métrica do projeto, medida a cada release.
- Atualização automática, fórmula do Homebrew e comando `cadex` no terminal são extras possíveis,
  cada um com a própria decisão; nenhum deles pode virar requisito para instalar.

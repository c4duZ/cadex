# 0007 — Instalação em um passo

Data: 2026-10-19 · Status: aceita (revista no mesmo dia: sem conta Apple Developer por enquanto)

## Contexto
O Cadex é para desenvolvedores que trabalham com agentes de IA, mas instalar tem que ser muito
fácil. Zig, Xcode e Swift são ferramentas de compilação; quem usa o app não pode precisar de nenhuma
delas.

Por enquanto não há conta Apple Developer, então o app não é notarizado. No macOS atual, um app não
notarizado baixado pelo navegador é bloqueado na primeira abertura: o usuário precisa ir em Ajustes >
Privacidade e Segurança e clicar em "Abrir mesmo assim". Arquivo baixado por `curl` não recebe a marca
de quarentena, e o Gatekeeper não bloqueia.

## Decisão
- **Instalação principal: um comando.** `curl -fsSL <url>/install.sh | sh` baixa o app, coloca em
  Aplicativos e termina. É o jeito que o público do Cadex já instala as ferramentas dele.
- **DMG como alternativa:** abrir, arrastar para Aplicativos. Sem notarização, a primeira abertura
  passa pelo "Abrir mesmo assim"; a página de download explica isso com uma imagem.
- Tudo o que o app usa vai dentro dele: o núcleo Zig, a libghostty-vt e o tree-sitter compilados no
  binário, recursos e licenças no bundle. Sem dependência instalada à parte, sem permissão de
  administrador.
- O app é assinado ad hoc (sem certificado), o mínimo para rodar no Apple Silicon.
- Binário universal (Apple Silicon e Intel). Funciona offline desde a primeira abertura.

## Consequências
- O script de instalação é parte do produto: curto, legível, sem `sudo`, e testado em cada release.
- Dependência nova só entra se puder ir dentro do bundle.
- O tamanho do download é métrica do projeto, medido a cada release.
- A receita de build universal, assinatura ad hoc e DMG vem do BKDict (projeto vizinho que já
  distribui assim): ver `../../apps/macos/packaging/CLAUDE.md`.
- **Rever quando o Cadex tiver público fora dos desenvolvedores:** aí a conta Apple Developer (Developer
  ID + notarização) passa a valer o custo, e o DMG vira o caminho principal.
- Atualização automática, Homebrew e comando `cadex` no terminal são extras possíveis, cada um com a
  própria decisão; nenhum pode virar requisito para instalar. A atualização dentro do app foi
  decidida em `0016-in-app-updates.md`.

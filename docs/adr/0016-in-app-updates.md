# 0016 — Atualização dentro do app, sem Sparkle

Data: 2026-10-20 · Status: aceita · Revê a última linha de `0007-one-step-install.md`

## Contexto
Até a 1.2.0, atualizar o Cadex era rodar o `install.sh` de novo ou baixar o DMG: o app não sabia
que havia versão nova. O dono quer um botão que atualiza com um clique, como o do Terax
(2026-10-20). O Terax usa o atualizador do Tauri, que não serve para um app Swift; o caminho comum
no Mac é o Sparkle, uma dependência grande que pede o app notarizado para funcionar bem, e o Cadex
não tem conta Apple Developer (ADR 0007).

## Decisão
- O próprio Cadex procura, baixa e instala a atualização, com o que o macOS já tem: `URLSession`
  para baixar, CryptoKit para conferir, `ditto` para abrir o ZIP e `FileManager.replaceItemAt` para
  trocar o app. Sem dependência nova.
- Cada release publica um `latest.json` (versão, notas, endereço do ZIP daquela versão, SHA-256 e
  assinatura). O app lê `releases/latest/download/latest.json` ao abrir e a cada 6 horas.
- O ZIP é assinado com Ed25519. A chave privada fica no Keychain do Mac que publica (item
  `cadex-update-signing`); a pública vai no código do app. Atualização com assinatura que não bate
  é recusada antes de tocar no app instalado: quem trocasse o arquivo da release não instalaria
  nada.
- Download feito pelo app não ganha a marca de quarentena, então a versão nova abre sem o "Abrir
  mesmo assim". A assinatura ad hoc presa ao bundle id (ADR 0007) mantém as permissões já dadas.
- O app troca a si mesmo e reabre pelo mesmo caminho do "Reabrir agora" das configurações, que
  pergunta pelos programas rodando antes de sair.

## Consequências
- `release.sh` só publica se achar a chave no Keychain; perder a chave obriga a trocar a pública
  no código, e quem estiver numa versão antiga terá que atualizar uma vez pelo `install.sh`.
  Uma cópia fica em `CADEX_UPDATE_KEY` no `.env` da raiz do repositório, fora do git (o dono,
  2026-10-20); o `.env` está no mesmo disco, então guardar outra fora deste Mac.
- Quem está na 1.2.0 ou antes não tem o botão: atualiza uma vez pelo `install.sh` ou pelo DMG.
- O app só se atualiza onde pode escrever: em /Applications de um usuário administrador ou em
  ~/Applications. Aberto direto do DMG ou de Downloads (translocado pelo macOS), ele explica e
  manda mover para Aplicativos.
- Windows fica para depois, com a mesma ideia e o mesmo `latest.json` estendido; os comandos são só
  do Mac por enquanto (`tools/check_command_parity.py`).
- Sparkle volta à mesa se o Cadex ganhar conta Apple Developer e precisar de atualização delta ou
  de canais (beta/estável).

# 0020 — Logos dos provedores de IA, exceção ao Phosphor

Data: 2026-10-21 · Status: aceita · Revê `docs/adr/0008-phosphor-icons.md` para este caso

## Contexto
O dono quer ver, em Agents › Accounts, no item de uso da barra de status e no popover das contas,
de qual provedor é cada conta: Claude, ChatGPT/Codex e, depois, Copilot, Cursor e Gemini (pedido de
2026-10-21). O Phosphor não tem logos de marca, e a regra do app é Phosphor em tudo.

## Decisão
- **Os logos vêm do Lobe Icons (MIT),** as versões de uma cor, que viram imagem modelo e pegam a
  cor do tema como os ícones Phosphor. O Gemini vem do Simple Icons (CC0), porque o do Lobe não
  converteu. O Simple Icons não tem mais o da OpenAI (retirado a pedido da marca).
- Gerados por `tools/icons/build_provider_logos.py`, com as versões fixadas, em PDF (o app roda do
  macOS 13, que não lê SVG), em `apps/macos/shared/icons/Resources/ProviderLogos`, usados por
  `apps/macos/shared/icons/ProviderLogo.swift`. Crédito e licenças no `NOTICE`.
- **Só para nomear o provedor de uma conta.** Nunca como ícone do Cadex, de botão ou de comando, e
  nunca para parecer um app desses: o Cadex continua se identificando como Cadex (ADR 0019).

## Consequências
- Provedor novo é uma linha no script e um caso no `ProviderLogo`.
- Os logos são marcas dos donos; trocar de fonte não muda o uso permitido aqui.

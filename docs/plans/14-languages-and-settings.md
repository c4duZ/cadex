# Plano 14 — Inglês e português, e as configurações refeitas

Depende de: release 1.2.0 · Features: settings, command-palette e todas as que mostram texto ·
Decisões: `docs/adr/0015-english-default-two-languages.md`.

## O que eu quero
- O Cadex em inglês por padrão, com português como opção em Configurações → General → Language,
  no Mac e no Windows. Pedido do dono em 2026-10-20: "nem eu uso em português".
- As configurações reorganizadas: cada página com seções, cada opção no lugar dela (o shell e as
  perguntas do terminal em Terminal; o manter acordado numa página própria), e todas as explicações
  reescritas, curtas e claras, dizendo o que a opção muda. O dono achou as de hoje mal montadas.

## O que eu não quero
- Trocar ids de comandos ou chaves do settings.json.
- Arquivos de tradução à parte ou chaves abstratas: o texto em par no lugar de uso (ADR 0015).
- Uma tela que fica no idioma velho depois de reabrir.

## Como eu quero
**Fases:**
- **A. Base e configurações.** Módulo compartilhado de textos no Mac (`T(en, pt)`, o idioma lido
  uma vez ao abrir, a paleta achando pelos dois títulos); general.language no settings.json; o
  seletor com "Reabrir agora"; a janela de configurações refeita, com seções e explicações novas nos
  dois idiomas: General (idioma, arquivos, árvore), Terminal (shell, perguntas, texto e cursor,
  histórico e teclado), Keep awake (modo, ao abrir, tela, e a tampa explicada à parte), Themes,
  Shortcuts, About.
- **B. O resto do Mac.** Comandos (títulos e palavras-chave), menus, barra de título, dicas,
  paleta, explorer, git, editor, preview, mídia, Markdown, spaces, alertas e mensagens.
- **C. Windows.** O mesmo par no Zig, o seletor e a página de configurações refeita com as mesmas
  seções e textos.
- **D. Núcleo.** As mensagens de erro que o núcleo devolve, nos dois idiomas.

## Como validar
- `make check` passa a cada fase.
- Com general.language "en", nenhum texto em português na interface do Mac (fase B) e do Windows
  (fase C); com "pt", nenhum em inglês, fora o que vem de fora (sistema, git).
- Trocar o idioma oferece reabrir, e o Cadex volta no idioma novo com as mesmas abas.

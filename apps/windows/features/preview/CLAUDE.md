# preview (app Windows)

## O que eu quero
- O preview web do Mac no Windows: servidor local que o terminal ofereceu ou qualquer endereço,
  numa aba, com voltar, avançar, recarregar e o endereço editável.

## O que eu não quero
- Página com acesso aos arquivos ou ao app: sem objeto do app, `file:` recusado, dados só
  enquanto o app está aberto (InPrivate).
- Erro velho por cima da página nova; Edge desenhando a página de erro dele por cima da nossa.

## Como eu quero
- WebView2 pelo módulo `webview` (`../../../../docs/adr/0014-webview2-on-windows.md`).
- Porta de entrada: `preview.zig` (`open` faz o Document de uma aba, `identityFor` acha a aba de um
  endereço já aberto). `document.zig`: Preview (barra, linha de progresso, "Não foi possível conectar
  a <endereço>" com o motivo, título da página ou host:porta, Inspecionar no menu da página) e Host
  (navegador do sistema, título mudou, atalho do app vindo da página).
- `address.zig`: as regras do Mac, testadas: sem esquema, http para servidor local e https para o
  resto; só http e https; mesma aba para o mesmo endereço, aba em branco sempre nova.
- `commands.zig`: preview.open, preview.open-in-tab, preview.reload (Ctrl+R), preview.back, preview.forward, os ids,
  títulos e atalhos do Mac (`../../../macos/features/preview/PreviewCommands.swift`).
- Spec: `../../../../docs/spec/preview.md`.

## Como validar
- `make windows-app` compila os testes (cadex-preview-tests.exe); rodam na VM. Na VM:
  `python -m http.server` abre pela oferta do terminal, voltar, avançar e recarregar funcionam.

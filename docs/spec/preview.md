# preview

## Para que serve
Ver no Cadex a página do servidor que um agente subiu no terminal (`npm run dev`,
`python3 -m http.server`), ao lado do código, sem trocar para o navegador.

## Comportamento
- Comando "Abrir preview web" abre uma aba com uma barra de endereço e a página. A barra tem voltar,
  avançar, recarregar e o endereço editável; Enter carrega. Sem esquema, vale `http://` para servidor local (localhost, 127.x, rede
  local) e `https://` para o resto. Sites só em http também abrem. Um erro some quando a página
  seguinte carrega.
- A aba mostra o título da página.
- Quando a saída de um terminal mostra um endereço local (`http://localhost:5173`,
  `http://127.0.0.1:8000`, `http://0.0.0.0:3000`, `http://[::1]:8080`), aparece no canto do terminal
  a oferta "Abrir no preview" com o endereço, por alguns segundos. Clicar abre a aba (ou recarrega a
  aba de preview que já mostra esse endereço). A oferta não se repete para o mesmo endereço na mesma
  sessão.
- Link da página que abre janela nova abre no navegador do sistema.
- A página não tem acesso ao app nem a arquivos locais: sem ponte com o Cadex, sem `file://`, cookies
  e dados guardados só enquanto o app está aberto.
- ⌘R recarrega com a aba de preview ativa; "Inspecionar elemento" no menu de contexto da página abre
  o inspetor.

## Estados
- **Carregando:** barra de progresso fina embaixo do endereço.
- **Erro:** servidor fora do ar: "Não foi possível conectar a <endereço>" com o motivo; recarregar tenta de novo.
- **Pronto:** a página.

## Casos de borda
- Servidor reinicia (hot reload) -> a página do próprio servidor cuida; o Cadex não interfere.
- Endereço local em texto que não é URL (`localhost:3000` sem `http`) -> também oferece.
- Muitos endereços de uma vez (log repetido) -> uma oferta por endereço.

## Critérios de aceite
- [ ] `python3 -m http.server` no terminal faz a oferta aparecer, e ela abre a página.
- [x] Endereços locais são detectados nos formatos acima; os de fora (`https://example.com`) não.
- [x] A página não acessa `file://` nem objetos do app.
- [ ] Voltar, avançar e recarregar funcionam.

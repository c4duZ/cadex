# Os terminais do Cadex pelo telefone

Do iPhone, por SSH no Mac pela sua tailnet: entrar nas abas abertas no Cadex, abrir abas novas
que aparecem no Mac e ver no Safari o que o agente gerou. Plano 39
(`docs/plans/39-terminals-from-the-phone.md`).

## Uma vez, no Mac

1. **No Cadex**, em Configurações:
   - Terminal → **Manter os terminais quando o Cadex fecha**: ligado. Sem isso as abas não moram no
     daemon e o telefone não as vê. Vale para as abas abertas depois de ligar.
   - Tailnet → **Máquinas da tailnet**: ligado (para o `cadex share`).
2. **Login Remoto**: Ajustes do Sistema → Geral → Compartilhamento → Login Remoto ligado, com
   acesso só para o seu usuário.
3. **O `cadex` no PATH do SSH** (o `~/.local/bin` já está no seu PATH):

   ```sh
   ln -sf /Applications/Cadex.app/Contents/Helpers/cadex ~/.local/bin/cadex
   ```

4. **mosh** (opcional, recomendado: a conexão aguenta o 4G caindo e o telefone bloqueado):

   ```sh
   brew install mosh
   ```

5. **Tailscale** já roda no Mac. Anote o nome dele na tailnet (`tailscale status`, a primeira linha)
   ou o endereço 100.x (`tailscale ip -4`).

## Uma vez, no iPhone

1. **Tailscale** da App Store, entrando com a mesma conta do Mac.
2. Um app de terminal: **Termius** (grátis, tecla Ctrl na barra) ou **Blink Shell** (mosh nativo).
3. Um host novo: endereço = o nome do Mac na tailnet (ou o 100.x), usuário = o seu do Mac.
   Para não digitar senha: gere uma chave no app e cole a pública no Mac, numa linha de
   `~/.ssh/authorized_keys`. Com mosh instalado, marque Mosh no host.

## No dia a dia

Conecte no Mac e digite `cadex`:

```
cadex
   1  zsh
   2  claude  · working
bkdg-center
   3  claude  · waiting

number enters · n terminal · c Claude · Enter leaves
```

- **Um número** entra na aba: a mesma tela do Mac, ao vivo; o que você digita aparece lá também.
  A aba no Mac mostra o ícone do telefone enquanto você está nela.
- **n** abre um terminal novo num projeto, **c** abre o Claude (com a conta e a memória do
  projeto); a aba nasce no Mac e você já está nela.
- **Ctrl+\\ e depois d** volta para o menu do telefone sem fechar nada. Fechar o app do
  terminal também não fecha nada.

Os comandos diretos, para atalhos do app:

| Comando | O que faz |
|---|---|
| `cadex attach 2` | entra na aba 2 do menu |
| `cadex new cadex` | abre um terminal no projeto cadex (o começo do nome basta) |
| `cadex new cadex claude` | abre o Claude no projeto cadex |
| `cadex share arquivo.html` | o link do arquivo no Safari, por uma hora |
| `cadex share` | os links que ainda valem |

**Arquivos no Safari:** peça ao Claude o resultado num arquivo (HTML, PDF, imagem, Word, Markdown) e
que ele rode `cadex share <arquivo>`; toque no link. A página mostra o arquivo e tem Baixar; Word,
Excel e PowerPoint abrem pelo Abrir. Só os seus aparelhos da tailnet abrem o link.

## Enquanto o telefone está numa aba

- A tela fica do tamanho do telefone também no Mac (o menor dos dois), e volta quando você sai.
- O Cadex fechado: `cadex new` o abre; `cadex attach` só vê as abas que ficaram rodando.

## Quando algo não vai

| O `cadex` diz | O que fazer |
|---|---|
| `command not found: cadex` | o passo 3 do Mac |
| `Cadex keeps no terminals here` | o Cadex fechado, ou "Manter os terminais" desligado |
| `the terminal daemon is from an older version` | as abas abertas antes de atualizar o Cadex: feche e abra o Cadex com elas fechadas |
| `no terminal open in Cadex` | as abas são de antes de ligar "Manter os terminais": abra novas (`n`) |
| `this Mac is not on a tailnet` | o Tailscale do Mac desligado ou sem login |
| `Machines (Tailscale) is off` | Tailnet → Máquinas da tailnet, nas Configurações |
| lixo como `^[[?1;2c` no prompt | uma resposta do terminal do telefone que escapou: apague a linha (Ctrl+U) |

# 0019 — Agents: o Cadex observa os agentes, não roda nem fala com IA

Data: 2026-10-21 · Status: aceita · Revê a linha "IA embutida no app" do `CLAUDE.md` da raiz

## Contexto
O dono quer ver, no Cadex, as sessões de agente rodando em todas as contas do Claude Code da
máquina (estado, subagentes) e o uso do plano de cada conta, como fazem o Orca e o ai-usagebar
(pedido de 2026-10-21). O `CLAUDE.md` diz "IA embutida no app: não" e "launcher de agentes: ficou
de fora".

A prova de conceito (2026-10-21, Swift nativo, fora do repositório) mostrou de onde vêm os dados e
quanto custam:
- Cada conta é uma pasta de configuração (`~/.claude`, `~/.claude-*`). O login fica no Keychain,
  num item com o nome derivado do caminho da pasta, e o `/usr/bin/security` o lê sem aviso.
- Cada sessão viva tem um registro pequeno em JSON dentro da pasta da conta (estado, pasta, nome),
  e os subagentes têm um arquivo de descrição ao lado do log da sessão.
- O uso vem do mesmo serviço que o `/usage` do Claude Code consulta, uma requisição por conta.
- Custo medido: varredura completa abaixo de 5 ms; ~7 ms de CPU por conta a cada leitura de uso;
  vigiar os registros por FSEvents com eventos por arquivo, 0,015% de um núcleo parado (vigiar só
  a pasta não avisa escrita no lugar); ~3 MB de memória. O app parado usa ~61 MB.

## Decisão
- **Só observar.** O Cadex lê o que o Claude Code grava e mostra. Não inicia agente, não manda
  prompt, não chama modelo, não embute chat. Os agentes continuam numa aba de terminal. "IA
  embutida" e "launcher de agentes" continuam fora.
- **Login só de leitura.** O token é lido do Keychain pelo `/usr/bin/security`, a cada leitura, e
  nunca guardado pelo Cadex. Login vencido não é renovado: renovar pelo Cadex pode trocar a chave de
  renovação e deslogar o Claude Code naquela conta. O cartão pede para rodar `claude` na conta.
- **No app macOS, em Swift.** Keychain, FSEvents e `URLSession` são do sistema; o que se lê é
  pouco e simples. O Windows (com outro lugar de login) faz a parte dele quando o port chegar; se
  as duas leituras ficarem iguais, a parte comum desce para o núcleo.
- **Formato de outro programa, lido com defesa.** Os arquivos são internos do Claude Code e podem
  mudar. Campo que falta é pulado; nada trava; a página diz o que não conseguiu ler.
- **O fim do log, só numa parada (2026-10-21, notificações).** Para dizer por que um agente parou
  (permissão, pergunta, terminou), o Cadex lê os últimos 64 KB do log da conversa daquela sessão,
  uma vez, quando ela passa de trabalhando para esperando. Nunca o log inteiro, nunca fora de uma
  parada. Os hooks do Claude Code dariam o motivo exato, mas exigem escrever na configuração dele.
- **Sem fingir ser outro programa.** O ai-usagebar se identifica como o Claude Code nas
  requisições (auditoria de 2026-10-21, `docs/plans/17-sidebar-agents-status.md`); o Cadex se
  identifica como Cadex e espera quando o serviço pede.
- **Abrir o agente de uma conta (2026-10-21, pedido do dono).** A única coisa que o Cadex inicia:
  clicar numa conta (Agents › Accounts, ⌘K "Open an Account's Agent") digita no terminal com foco,
  se ele está no prompt, ou numa aba nova, `claude` com a pasta da conta em `CLAUDE_CONFIG_DIR`
  (ou `codex` com `CODEX_HOME`), e Enter. Com agents.launchSkipPermissions, o
  `--dangerously-skip-permissions` (Codex: `--dangerously-bypass-approvals-and-sandbox`), desligado
  por padrão. Como o ssh.connect: digitar um comando. O Cadex continua sem mandar prompt, sem ler
  resposta e sem falar com modelo; o "launcher de agentes" de várias tarefas continua fora.
- **Tudo desligável e com custo zero desligado.** Cada leitura tem uma chave; desligada, nenhum
  arquivo é vigiado e nenhuma requisição sai. O orçamento: tudo ligado, no máximo 10% acima do app
  sem as leituras no `make perf`.

## Alternativas recusadas
- **Usar o ai-usagebar ou outro programa por baixo:** dependência em Rust e processo à parte, contra
  o "instalar em um passo, sem dependências" (ADR 0007).
- **Copiar ou traduzir o código do Orca ou do ai-usagebar (os dois MIT):** ADR 0004. Só o
  comportamento, descrito nas specs.
- **Ler os logs completos das sessões para achar o estado:** arquivos de vários MB; o registro da
  sessão já diz o estado.
- **Renovar o login vencido:** risco de deslogar o Claude Code (acima).

## Consequências
- Specs: `docs/spec/agents.md`, `docs/spec/sidebar.md`, `docs/spec/ssh.md` e a barra de status
  personalizável em `docs/spec/status-bar.md`. Plano 17.
- Uma versão nova do Claude Code pode esvaziar a página até o Cadex acompanhar o formato.
- Só Claude Code nesta primeira vez. Codex e sessões na nuvem ficam para um plano próprio.

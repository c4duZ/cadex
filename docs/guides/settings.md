# Configurar o Cadex pelos arquivos (e por agentes)

Tudo o que se configura no Cadex é arquivo de texto, e o Cadex relê cada um sozinho: mudar o arquivo
com o app aberto vale na hora, sem reiniciar. Por isso um agente (Claude Code, Codex) configura o
Cadex editando esses arquivos, do mesmo jeito que a janela de configurações faz (o dono, 2026-11-22).

## Onde está cada coisa

| Arquivo | O que guarda | Editar? |
|---|---|---|
| `~/Library/Application Support/Cadex/settings.json` | todas as preferências e os atalhos | sim |
| `~/Library/Application Support/Cadex/orchestration/automations/<id>.json` | as automações, uma por arquivo | sim |
| `~/Library/Application Support/Cadex/themes/<nome>.json` | os temas do dono | sim |
| `<repositório>/.cadex/environment.toml` | o ambiente descartável das tarefas do repositório | sim, no repositório |
| `projects.json`, `worktrees.json`, `history.sqlite`, `orchestration/state.sqlite`, `kit/`, `usage/`, `memory/`, `sessions/` | o estado e os registros do app | não: só leitura |

O que sobra no UserDefaults do macOS é estado da interface, não configuração: as pastas abertas na
árvore de arquivos e a versão que o dono mandou pular na atualização.

## A referência completa
Fica num lugar só, em inglês, porque é o guia que os agentes leem:
`../../core/features/agent-tools/guides/settings.md`. Ele vem dentro do programa `cadex`, então uma
sessão aberta pelo Cadex o lê com `cadex skills get settings`, e a skill `cadex-settings` do plugin
do Cadex leva o agente até ele quando o dono pede para mudar alguma coisa do app. Ele tem:
- cada chave do `settings.json`, com o tipo, o padrão, os valores ou o intervalo, e o que faz;
  as que só valem ao reabrir estão marcadas;
- o formato dos atalhos (`"cmd+shift+t": "tab.new"`, `null` desliga um padrão); os ids de todos os
  comandos estão em `commands.md`, gerado do código;
- o arquivo de uma automação, com um exemplo que os testes leem;
- o arquivo de tema e a receita `environment.toml`;
- o que um agente não liga sem o dono pedir com todas as letras (o que gasta dinheiro, abre a rede
  ou age sem ele).

## As regras que valem para todos
- Campo errado volta ao padrão e o resto do arquivo continua valendo; número fora do intervalo vai
  para o limite mais perto. O motivo vai para o log.
- Arquivo de automação ou de tema que não lê fica de fora, com o motivo; os outros valem.
- Nada de chave, token ou senha em nenhum desses arquivos.

## Como isso fica certo
- `make macos-test` confere que toda chave que o `settings.json` grava está na referência, que o
  exemplo de automação dela lê como automação e que o exemplo de tema lê como tema.
- `make manifests` confere que `commands.md` é o que o código registra
  (`../../tools/gen_commands.py --check`); chave ou comando novo sem documentação quebra os dois.

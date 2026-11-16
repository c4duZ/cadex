# 0032 — Receita de ambiente por repositório e o ambiente descartável de uma tarefa

Data: 2026-11-16 · Status: aceita · Apoia-se em `docs/adr/0030-installed-tailscale.md` e em
`docs/adr/0031-run-on-remote.md` · Comportamento de referência: as receitas do Orca (`orca.yaml`),
sem código dele (`docs/adr/0004-clean-rewrite.md`) · Plano `docs/plans/23-machines.md`

## Contexto
Uma tarefa de agente às vezes precisa de um ambiente que não é este Mac: um Ubuntu com as
dependências do projeto, um banco, um serviço rodando numa porta. O dono quer subir isso no Docker
do PC de mesa, mandado daqui, e ver os serviços no preview pelo nome (`http://ubuntu-dev:3000`).
Quando a tarefa acaba, o ambiente deve ir embora junto (o dono, 2026-11-14).

O Docker já fala com outra máquina sem nada novo: um contexto (`docker context create <nome>
--docker host=ssh://<usuário>@<máquina>`) leva os comandos ao daemon de lá pelo ssh. E um
contêiner com o Tailscale ao lado (o "sidecar") entra na tailnet como mais uma máquina, com nome
próprio, e os outros chegam nas portas dele pelo nome.

## Decisão
- **A receita mora no repositório**, em `.cadex/environment.toml` (criada em cada repositório que
  quiser; o Cadex não cria sem o dono pedir). Diz:
  - a imagem ou o Dockerfile;
  - a máquina onde roda (este Mac ou uma da tailnet / do `~/.ssh/config`; ausente, pergunta);
  - as portas que o serviço abre;
  - o comando de preparo, rodado dentro do contêiner depois de criado;
  - o sidecar do Tailscale, se quiser: o nome da máquina e de onde vem a chave (`TS_AUTHKEY`, lida
    do ambiente do dono na hora de subir).
- **O Cadex roda o `docker` do dono**, local ou por contexto remoto, e nada mais: não fala com
  nuvem nenhuma, não tem cliente do Docker dentro, não instala o Docker. Sem o binário, os
  comandos dizem isso e param.
- **O contexto é por aba, nunca global.** A aba ganha `DOCKER_CONTEXT` no ambiente dela; o Cadex
  nunca roda `docker context use`, que mudaria o contexto de todos os terminais do dono.
- **Nenhuma chave guardada.** A chave do Tailscale de um contêiner é colada pelo dono no ambiente
  dele (ou referenciada na receita pelo nome da variável) e lida na hora; o Cadex não a grava em
  configuração, log ou receita.
- **O ambiente segue a tarefa.** "Nova tarefa" com receita cria o contêiner na máquina escolhida,
  roda o preparo e abre o agente dentro dele. Hibernar a tarefa (plano 19) suspende o contêiner;
  abrir de novo retoma; apagar a worktree destrói o contêiner, com confirmação. Comandos
  worktrees.environment-up, -suspend, -resume e -destroy.
- **Só contêiner nesta fase.** VM em nuvem (Fly, Modal e outras) fica fora; entraria com ADR
  própria, porque aí há conta, custo e chave de terceiro.

## Alternativas recusadas
- **A receita guardada no Cadex, fora do repositório:** não viaja com o projeto e cada máquina
  teria a sua.
- **`devcontainer.json` como formato:** traz junto o resto da especificação de dev containers (o
  editor, as extensões, o VS Code) e muda num ritmo que não é o nosso. Ler um devcontainer existente
  como ponto de partida pode vir depois, sem trocar o formato.
- **Usar a API do Docker direto (o socket):** pede outra implementação para o caso remoto; o
  binário do dono já resolve local e ssh do mesmo jeito.
- **`docker context use`:** muda o estado global do dono por baixo dele.
- **Guardar o `TS_AUTHKEY` para não pedir de novo:** é uma chave que entra aparelhos na tailnet do
  dono; fica com ele.

## Consequências
- `docs/spec/machines.md` (Docker pela tailnet) e `docs/spec/worktrees.md` (ambiente descartável).
- Um repositório pode ter `.cadex/environment.toml` versionado: quem clona vê a receita, nunca uma
  chave.
- Guardar chave, mudar o contexto global do Docker ou falar com nuvem sem ADR nova é desfazer esta
  decisão.

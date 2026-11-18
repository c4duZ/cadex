# Plano 32 — Configurações organizadas e a memória por projeto numa tela

Depende de: plano 31 · Features: settings, shared/customize, status-bar, agents, memory ·
Decisões: `docs/adr/0035-work-frame.md`, `docs/adr/0028-project-memory.md` · Origem: o dono,
2026-11-18: "as configurações não estão aparecendo… é cheio de módulo novo"; "a status bar também
vai vir para cá, as configurações que estão em outra coisa hoje"; a memória "sempre ligada
automaticamente" e o .ai-memory.toml do projeto "numa tela, ao invés de ficar mexendo nas coisas".

## O que eu quero
- Uma janela de configurações só, com uma lista de seções à esquerda (como os Ajustes do macOS) e
  uma busca no topo que acha qualquer configuração pelo nome ou pelo texto dela.
- Cada módulo na sua seção: Geral, Aparência, Terminal, Arquivos, Git e revisão, Agentes (com as
  contas), Notificações, Memória, Muitos agentes, Máquinas e SSH, Barra de status, Atalhos, Sobre.
- O que hoje fica noutra janela (Personalizar: a barra de status e as contas) dentro dela; a janela
  Personalizar sai.
- A memória ligada sem ninguém pedir, e a configuração de cada projeto (o .ai-memory.toml) numa
  tela: nome do projeto, o que fica de fora, o briefing, subagentes, busca, perfil, retomada.

## O que eu não quero
- Uma página "Geral" com tudo dentro.
- Editar TOML à mão para o que a tela oferece; perder no arquivo o que a tela não conhece
  (comentários, chaves de outra versão do ai-memory).

## Como eu quero
- **A. A janela.** A lista à esquerda (ícones Phosphor, a seção aberta marcada como a linha
  escolhida do painel da direita), a página à direita nas peças da moldura (plano 31 D), a busca
  filtrando as linhas de todas as seções. Os comandos que abriam uma página (settings.open-terminal,
  settings.open-themes) abrem a seção.
- **B. Os módulos nas seções.** Cada linha da página Geral de hoje vai para a seção dela; a barra
  de status e as contas (a lista de arrastar e ligar do Personalizar) viram as seções Barra de status
  e Agentes › Contas; a janela Personalizar e os comandos dela abrem a seção nas configurações.
- **C. Memória sempre ligada.** Com o agente de memória ligado e as propostas sem esperar aprovação
  (a ADR 0037, que esperava o código), numa migração (Settings.version 7) para quem vem de antes. Nasce ligada e fica: nada pede "Ligar" no caminho; desligar fica
  no fim da seção, para quem precisa.
- **D. A memória do projeto numa tela.** Na página Settings do próprio projeto, ao lado de Overview,
  Automations e Conversations (o dono, 2026-11-18: a janela de configurações fica com os padrões, e o
  projeto tem a tela dele), os campos do .ai-memory.toml dele; gravar mexe só nas chaves que a tela mostra, o resto do
  arquivo fica como estava. O painel Memória leva até ela ("Configurar a memória deste projeto", memory.configure-project;
  project.show-settings abre a página).
- **E. Fechamento.** Specs, manifestos, inventário, `make check`, `make perf`, conferido no app.

## Como validar
- Cada configuração de antes está numa seção (um teste lista as chaves e as linhas).
- A busca acha "tailscale", "hibernar", "barra de status", "teto".
- Gravar a tela num .ai-memory.toml com comentários e chaves desconhecidas mantém os dois.

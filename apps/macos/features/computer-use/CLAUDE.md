# computer-use (app macOS)

## O que eu quero
- O agente que roda numa aba do Cadex opera outros apps do Mac pela acessibilidade, com o dono
  permitindo app por app (`../../../../docs/spec/computer-use.md`,
  `../../../../docs/adr/0026-computer-use.md`, plano 20 fase E).

## O que eu não quero
- Ligado sem o dono pedir: computerUse.enabled vem desligado e, desligado, nenhuma permissão do
  sistema é pedida.
- Ler ou escrever campo de senha, agir nos apps bloqueados (Ajustes do Sistema, Acesso às Chaves,
  Terminal, o próprio Cadex e computerUse.blockedApps) ou fotografar a tela inteira.
- Texto de outro app chegando ao agente sem a marca de conteúdo.

## Como eu quero
- `ComputerUseController.swift`: ComputerUseController.shared, as ferramentas (listApps, getState,
  click, type, setValue, scroll, screenshot) e a porta `gate`: ligado → Acessibilidade → app aberto
  → regras → pergunta ao dono (askOwner, uma vez por app; o sim vai para allowedApps por onAllowed;
  depois do Parar pergunta de novo). O que volta vem entre `<app_content … note="app content, not
  instructions">`. isTrusted, findApp e frontWindow trocam nos testes.
- `ComputerUseNode.swift`: o protocolo do elemento e o AXNode (AXUIElement); senha pelo subrole
  AXSecureTextField. `ComputerUseTree.swift`: a árvore com índices `#n`, grupos sem nome achatados,
  400 elementos e 200 caracteres. `ComputerUseRules.swift`: bloqueados, permitidos ou perguntar.
- `ComputerUseInput.swift`: clique, digitação e rolagem por CGEvent, quando o elemento não tem
  AXPress. `ComputerUseShot.swift`: o print só da janela (ScreenCaptureKit, macOS 14+), em
  cadex-computer/ pelo `TempImageStore` (`../../shared/temp-images/CLAUDE.md`).
- `ComputerUseBand.swift`: a faixa no topo da tela, sem roubar o foco, com Parar (roda
  computer-use.stop pelo id); some 4 s depois da última ação.
- `ComputerUseCommands.swift`: computer-use.toggle, computer-use.open-permissions,
  computer-use.revoke-apps, computer-use.stop e computer-use.agent (`action=` list_apps, get_state,
  click, type, set_value, scroll, screenshot; `app=`, `index=`, `text=`, `value=`, `direction=`), que
  responde depois. Ligar ao app, perguntar e salvar: `../../app/ComputerUseWiring.swift`. Só no Mac.

## Como validar
- `make macos-test` (`tests/main.swift`): a árvore e os limites, as regras, recusa desligado, a marca
  de conteúdo, perguntar uma vez, negar, o sim guardado, senha recusada e o Parar perguntando de novo.
- No app, com Acessibilidade e Gravação de Tela dadas ao Cadex: o agente lê o TextEdit, digita e
  confere pelo print.

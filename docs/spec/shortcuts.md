# shortcuts

## Para que serve
Disparar comandos pelo teclado. Cada atalho é só uma combinação de teclas apontando para o id de um
comando; o usuário pode mudar qualquer um.

## Comportamento
- Os atalhos padrão vêm com o app. Os do terminal e das abas:
  - ⌘K paleta · ⌘L limpar · ⌘C copiar · ⌘V colar · ⌘A selecionar tudo · ⌘F buscar
  - ⌘T nova aba · ⌘W fechar painel · ⌘1 a ⌘9 ir para a aba
  - Ctrl+Tab e Ctrl+⇧+Tab alternar abas pela ordem de uso
  - ⌘D dividir à direita · ⌘⇧D dividir para baixo · ⌘] e ⌘[ próximo e anterior painel
  - ⌘⌥ + setas mudar o foco para o painel naquela direção
  - ⌘↑ e ⌘↓ topo e fim do histórico
- O usuário muda atalhos num arquivo de preferências (`shortcuts.json` em Application
  Support/Cadex): um mapa de combinação de teclas para id de comando. A tela de configuração vem
  com a feature settings.
- Um atalho personalizado substitui o padrão da mesma combinação. Apontar uma combinação para
  `null` desliga o padrão dela.
- Atalhos do app nunca usam Ctrl sozinho com letra (Ctrl+B, Ctrl+R, Ctrl+A...): essas teclas são
  dos programas no terminal. Ctrl+Tab é a exceção, porque os shells não usam.
- O menu mostra o atalho em vigor de cada comando.

## Estados
- **Sem arquivo de preferências:** só os padrões.
- **Arquivo inválido** (JSON quebrado): os padrões valem e o problema é registrado no log; o app
  abre normalmente.

## Casos de borda
- Combinação personalizada para um id que não existe: ignorada, com aviso no log.
- Duas combinações personalizadas para o mesmo comando: as duas funcionam.
- Combinação personalizada já usada por outro comando padrão: a personalizada vence; a detecção de
  conflito avisa qual padrão foi tirado.
- Combinação com Ctrl+letra: recusada, com aviso no log, para não roubar tecla do terminal.

## Critérios de aceite
- [x] Todo atalho padrão aponta para um comando registrado.
- [x] Não há dois atalhos padrão com a mesma combinação.
- [x] Um `shortcuts.json` com `"cmd+shift+t": "tab.new"` faz ⌘⇧T abrir aba nova.
- [x] Um `shortcuts.json` quebrado não impede o app de abrir.

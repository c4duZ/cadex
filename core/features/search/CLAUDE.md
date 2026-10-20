# search (núcleo)

## O que eu quero
- Busca de arquivos por nome, fuzzy, rápida o bastante para cada tecla digitada.
- Busca de conteúdo (texto e regex) com o resultado chegando aos poucos.
- Respeitar .gitignore, .ignore e arquivos ocultos conforme a preferência.

## O que eu não quero
- Busca que trava o app ou não pode ser cancelada.
- Uma busca nova competindo com a anterior: a anterior é cancelada.

## Como eu quero
- Porta de entrada: `search.zig`. `fuzzy.zig` pontua um texto (letras em ordem; caixa e acentos do
  português não importam; começo de palavra vale mais) e `rank.zig` ordena uma lista (paleta).
- `walker.zig` percorre o workspace: só arquivos, sem `.git`, sem ignorados (`core/shared/ignore.zig`),
  sem as pastas de dependência, cache e build de `skipped_folders` (e Library/AppData na pasta
  pessoal), ocultos só se pedido, sem seguir links, até o orçamento (`limit`), ordem por nome.
  `nearby.zig`: o caminho de perto para longe a partir de um foco (a pasta e tudo abaixo, depois
  as vizinhas de cada nível acima) e `Covered`, as pastas lidas por inteiro.
- ⌘P: `index.zig` guarda os nomes em memória numa thread própria e se atualiza com o watcher do
  explorer, relendo só a pasta que mudou (subpastas novas inteiras, sumidas removidas). Só começa
  na primeira consulta (`start`), guarda até 100 000 nomes a partir do foco (`setFocus`, a pasta
  do terminal), refaz quando o foco cai fora do que leu e ignora mudanças fora dele;
  `files.zig` ordena (nome do arquivo vale mais que as pastas, filtro barato antes do fuzzy).
- ⌘⇧F: `content.zig` busca numa thread, entrega em lotes de 64, uma ocorrência por linha, até 2 000,
  pula binário e arquivo acima de 2 MB; `cancel()` só volta depois do último callback.
  `content_match.zig`: texto literal pelo núcleo, regex pela TRE compilada no núcleo (ERE com
  `\d \w \s \b`, igual no Mac e no Windows, `docs/adr/0013-regex-tre.md`).
- API C: `c_api.zig` (fuzzy), `c_api_files.zig` (índice), `c_api_content.zig` (conteúdo).
- Spec: `docs/spec/search.md`. Status: núcleo pronto (plano 4, fase D); a paleta é a fase E.

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- Testes com pastas temporárias: .gitignore, índice acompanhando criação e remoção, busca literal e
  regex, limite, cancelamento sem resultado depois (`content_test.zig`).
- `fuzzy.zig` e `rank.zig` testam a ordem ("na" põe "Nova aba" na frente), acentos e posições.

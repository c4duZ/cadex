# editor (núcleo)

## O que eu quero
- Destaque de sintaxe e regiões de dobra para as linguagens comuns, com o tree-sitter.
- Atualizar só o trecho alterado quando o arquivo muda (reparse incremental).

## O que eu não quero
- Language server, autocomplete de código, vim ou formatar ao salvar
  (`../../../docs/adr/0006-editor-reads-code-edits-markdown.md`).
- Gramática de linguagem carregada sem o usuário abrir um arquivo dela.
- Travar em arquivo gigante: acima de um limite, mostra sem destaque.

## Como eu quero
- tree-sitter e as gramáticas em C, compilados pelo Zig; o tree-sitter entra no `NOTICE` junto.
- A porta de entrada devolve faixas (início, fim, tipo de trecho) e regiões de dobra; o app só pinta.
- Spec de comportamento em docs/spec/editor.md, escrita antes do código. Status: não iniciada.

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- Teste: destaque e dobras de um arquivo de exemplo por linguagem batem com o esperado.

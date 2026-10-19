# terminal

> Spec em construção. Comportamento inicial: igual ao terminal do Terax, sem modo em blocos e sem
> terminal privado. Seções ainda não escritas estão marcadas como "a escrever".

## Para que serve
Rodar o shell do usuário dentro do Cadex, em abas e painéis, com a mesma resposta de um terminal
nativo rápido. É onde os agentes de código rodam.

## Comportamento

### Colar (⌘V)
Ao colar, o terminal olha o que está na área de transferência, nesta ordem, e usa o primeiro que
existir:

1. **Arquivos copiados** (por exemplo, no Finder): cola os caminhos completos, cada um escapado para
   o shell (espaços e caracteres especiais protegidos), separados por espaço.
2. **Imagem** (print de tela, imagem copiada do navegador): salva a imagem como PNG num arquivo
   temporário e cola o caminho desse arquivo, escapado para o shell.
3. **Texto**: cola o texto. Se o programa em execução ativou o modo bracketed paste, o texto vai
   marcado como colagem, para não ser executado linha a linha como digitação.

Colar é responsabilidade da interface de cada plataforma: no macOS, a área de transferência do
sistema (NSPasteboard); no Windows, a do Win32. O núcleo recebe só o texto final a enviar.

### Atalhos
- ⌘K abre a paleta de comandos, mesmo com o foco no terminal.
- ⌘L limpa a tela.
- Demais atalhos: a escrever.

### A escrever
Abas e divisões; redimensionar; busca no terminal; links clicáveis; seleção e copiar; arrastar
arquivos para dentro; aviso ao fechar com processo em primeiro plano; restaurar sessões.

## Casos de borda
- Área de transferência vazia: ⌘V não envia nada.
- Vários arquivos copiados: todos os caminhos, na ordem copiada.
- Imagem e texto juntos na área de transferência (comum ao copiar do navegador): vale a imagem.
- Falha ao salvar a imagem temporária: avisa o erro e não cola nada.

## Critérios de aceite
- [ ] Copiar um arquivo com espaço no nome no Finder e colar resulta num caminho que o shell aceita.
- [ ] Colar um print de tela cola o caminho de um PNG que existe e abre a imagem.
- [ ] Colar texto num programa com bracketed paste ativo não executa as linhas automaticamente.
- [ ] ⌘K com o foco no terminal abre a paleta e não envia nada ao shell.

# strings (compartilhado do app)

## O que eu quero
- Os textos da interface em inglês (padrão) ou português, escritos em par onde são usados
  (`../../../../docs/adr/0015-english-default-two-languages.md`).

## O que eu não quero
- Arquivo de tradução à parte, chaves abstratas ou texto da interface fora de um par.
- Trocar o idioma com o app aberto: o app lê Strings.language uma vez, ao abrir.

## Como eu quero
- `Strings.swift`: `T(en, pt)` devolve o texto no idioma da interface e guarda o outro, que a
  paleta usa para achar um comando pelos dois títulos (Strings.counterpart). O app chama
  Strings.setLanguage com o general.language do settings.json antes de montar qualquer tela, o que
  também passa o idioma ao núcleo (cadex_set_language, para as mensagens do git e o nome de cópia).

## Como validar
- `make macos-test` passa: idioma escolhido e a versão do outro idioma.

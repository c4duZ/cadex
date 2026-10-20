# shortcuts (app Windows)

## O que eu quero
- Atalhos como no Mac: teclas → id de comando, padrões no próprio comando, os do usuário na seção
  `shortcuts` do settings.json, o mesmo arquivo do Mac.
- A tradução do Mac para o Windows numa regra só: ⌘ é Ctrl+Shift; ⌘ com ⇧ ou ⌥ é Ctrl+Shift+Alt;
  ctrl, alt e shift escritos valem como estão; símbolos seguem o layout (ABNT2 também).

## O que eu não quero
- Ctrl sozinho com letra como atalho do app: é dos programas no terminal (spec de shortcuts).
- Tecla de atalho chegando ao terminal quando o comando rodou; nem engolida quando ele não pode rodar.

## Como eu quero
- Porta de entrada: `shortcuts.zig` (Shortcuts: handle de cada tecla antes de tudo, label para a
  paleta e os menus, reload quando o settings.json muda).
- `key_combo.zig`: KeyCombo (parse da notação do Mac, label "Ctrl+Shift+D", a recusa de Ctrl+letra).
- `keymap.zig`: Keymap (padrões, preferências que trocam, desligam com null ou são recusadas, e os
  problemas para o log).
- Spec: `../../../../docs/spec/shortcuts.md`.

## Como validar
- `make windows-app` compila os testes desta feature; rodam na VM.

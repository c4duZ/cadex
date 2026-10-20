# themes (app Windows)

## O que eu quero
- Os mesmos 46 temas do Mac, lidos do mesmo catalog.json (`../../../macos/features/themes/Resources/catalog.json`,
  embutido pelo build), Caffeine padrão, seguindo o claro/escuro do Windows por padrão.

## O que eu não quero
- Cópia do catálogo dentro de apps/windows.

## Como eu quero
- Porta de entrada: `themes.zig` (Store: família e modo escolhidos, `refresh` quando o Windows troca
  de modo; `style` para a camada de interface; `terminalColors` para o núcleo).
- `theme.zig`: Theme, Family e a leitura de cada versão (cores #RGB, #RRGGBB, #RRGGBBAA; 16 ANSI).
- `catalog.zig`: o catálogo embutido, lido uma vez.
- O modo do sistema vem do registro (AppsUseLightTheme); o app relê em WM_SETTINGCHANGE.
- Spec: `../../../../docs/spec/themes.md`.

## Como validar
- `make windows-app` compila os testes (o catálogo tem os 46 temas); rodam na VM.

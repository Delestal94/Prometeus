# N-966.4: las ayudas estáticas siguen las teclas y botones reasignados (2026-10-19)

Lo hizo Nacho (con Claude), rama `nacho/N-966.4-remap-walkthrough`. Toca archivos de Slatex (UI):
- `scripts/ui/control_hints.gd` (nuevo): arma un texto con `%s` a partir de las acciones reales
  (`GameSettings.key_label` / `pad_label`); `WASD` y "Stick izq." salen del grupo de acciones que caminan.
- `scripts/ui/hud/hud_prompts.gd`, `hud.gd`, `hud_pause.gd`, `hud_notices.gd`: la barra de atajos, la pista de rol,
  el prompt de interactuar / soltar / abrir tapa, los pasos de inicio, la carta y el aviso de poca visibilidad
  usan las teclas y botones del jugador.
- `scripts/ui/options_panel.gd` + `options_controls_section.gd` (señal `refreshed`): el resumen de controles se
  reescribe al reasignar.
- `scripts/presentation/phone_camera.gd`, `newspaper/newspaper_director.gd`, `gameplay/player/player_cargo_care.gd`:
  la tecla/botón de guardar el celular, de saltar la tapa y de interactuar en la tarjeta de cuidado.
- `translations/strings_ui.csv`: `HUD_KEYS_*`, `HUD_KEY_CREW/PHONE/PING`, `HUD_PAD_*`, `HUD_PHONE_HINT_*`,
  `UI_OPT_CONTROLS_*`, `HUD_CARD_USE_PAD`, `HUD_LOW_VISIBILITY_GUIDE_PAD` ahora llevan `%s` donde iba la tecla;
  se borra `HUD_PAD_DOWN` (sin uso).
- Slatex: un texto de ayuda nuevo con una tecla va con `%s` y `ControlHints`, no con la tecla escrita.

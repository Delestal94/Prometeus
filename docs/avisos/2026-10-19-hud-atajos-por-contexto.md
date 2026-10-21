# 2026-10-19 · N-977: atajos del HUD por contexto y piso del fondo de texto

Toca `scripts/ui/hud/hud_prompts.gd`, `scripts/ui/options_panel.gd` y `scripts/core/game_settings.gd` (dominio de Slatex / zona compartida).

- La línea de atajos muestra 3-4 según el rol (a pie/pasajero, al volante); "centrar vista" ya no aparece ahí.
- `text_backdrop_opacity` ya no baja de 0,3 (`GameSettings.TEXT_BACKDROP_MIN`); el slider de opciones arranca en 0,3.

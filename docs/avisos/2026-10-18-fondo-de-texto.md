# N-969: ajuste "Fondo del texto" (2026-10-18)

Lo hizo Nacho (rutina de construcción), rama `nacho/N-969-text-backdrop`. Toca archivos de Slatex (UI):
- `scripts/core/game_settings.gd`: `text_backdrop_opacity` (0-1, default 0,88), señal `text_backdrop_opacity_changed`,
  guardado en `SAVED_KEYS` y en `reset_to_defaults()`.
- `scripts/ui/hud/hud.gd`: `apply_text_backdrop()` ajusta la placa de `interaction_label` (prompts y subtítulos).
- `scripts/ui/options_panel.gd`: slider "Fondo del texto" bajo "Subtítulos de sonidos".
- `translations/strings_ui.csv`: `UI_OPT_TEXT_BACKDROP`.
Ninguna firma existente cambia. Con el default el HUD se ve igual que antes.
- Slatex: nada que hacer.

# D-0606.c1: teclas del mástil del autoelevador en Opciones (zona compartida)

Tocado en zona compartida o en archivos de otro dominio:
- `scripts/core/game_settings.gd`: `forklift_mast_up` / `forklift_mast_down` pasan a `REBINDABLE_ACTIONS`, con tecla de fábrica (flechas) y contexto `CONTEXT_DEPOT`.
- `scripts/ui/options_controls_section.gd`, `translations/strings_ui.csv`: grupo "Autoelevador" con dos filas.
- `translations/strings_world.csv`: `WORLD_FORKLIFT_DRIVING` lleva `%s` por cada tecla (se arma con `GameSettings.binding_label`).
- `tests/test_options_controls.gd`: las dos acciones salen de "no ofrecidas" y entran al inventario.

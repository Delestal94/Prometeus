# N-966.3: remapeo de mando desde Opciones (2026-10-19)

Lo hizo Nacho (rutina de construcción), rama `nacho/N-966.3-gamepad-remap`. Toca archivos de Slatex (UI):
- `scripts/ui/options_controls_section.gd`: cada fila suma un botón de mando (botón o dirección de stick / gatillo)
  junto al de la tecla; "Original" restaura tecla y botón. Al esperar un botón del mando, B se asigna como cualquier
  otro: cancelan Start, Esc, un clic afuera o 6 s sin tocar nada (nadie queda trabado con solo el mando). Foco
  izquierda / derecha entre tecla y mando.
- `scripts/core/game_settings.gd`: `pad_bindings` (solo lo que difiere de `project.godot`, en `SAVED_KEYS`),
  `rebind_pad()` / `reset_pad_binding()` con el mismo swap / bloqueo que el teclado, `bound_pad()`, `pad_label()`,
  `key_label()`. `binding_label()` ahora devuelve el mando si fue lo último que se tocó y la acción tiene botón;
  con teclado en mano devuelve lo mismo que antes.
- `scripts/core/pad_binding.gd` (nuevo): códigos, nombres y reservados (Start, Y reiniciar, stick de mirar, gatillo
  derecho de agarrar, obturador del celular).
- `translations/strings_ui.csv`: `UI_OPT_PAD_*`, `UI_OPT_BIND_PAD_*`, `UI_OPT_PRESS_PAD*`, `UI_OPT_BIND_KEY_TIP/PAD_TIP`;
  cambia el texto de `UI_OPT_BIND_DEFAULT_HINT`.
Pendiente en N-966.4: los textos de ayuda estáticos siguen con los botones por defecto.
- Slatex: nada que hacer.

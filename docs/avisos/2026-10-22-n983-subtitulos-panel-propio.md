# N-983: subtítulos en su propio panel, keycap en el aviso y tamaño elegible

Tocado en archivos del dominio de Slatex: `scripts/ui/hud/hud.gd` (`interaction_label` pasa de `Label` a
`RichTextLabel`; nuevos `prompt_stack` y `subtitle_label`; la tarjeta de carta arriba a la derecha sin
autowrap), `scripts/ui/hud/hud_prompts.gd` (`render_interaction_prompt` arma aviso y subtítulos por
separado), `scripts/ui/hud/hud_notices.gd` (`fit_card_line`), `scripts/ui/options_panel.gd` (tamaño de
subtítulos) y `scripts/ui/ui_theme.gd` (`CREAM`). Zona compartida: `scripts/core/game_settings.gd`
(`subtitle_scale`, en `SAVED_KEYS`). Archivo nuevo: `scripts/ui/hud/hud_prompt_plates.gd`.

- `hud.interaction_label` es ahora un `RichTextLabel` (BBCode con keycaps): los tests leen
  `get_parsed_text()`. Los subtítulos de sonido ya no van ahí sino en `hud.subtitle_label`.
- `HUD_PROMPT_DROP` ya no lleva corchetes: `%s  Soltar paquete` (la tecla se dibuja como keycap).
- Los textos con corchetes ("[vidrio que cruje]") se escapan con `HudPrompts.escape_bbcode`.

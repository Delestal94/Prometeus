# 2026-10-21 · HUD: textos permanentes a 12 px efectivos (N-982)

Nacho tocó `scripts/ui/hud/hud.gd` y `hud_cargo_panel.gd` (dominio de Slatex): nuevas constantes
`Hud.HUD_MIN_FONT_SIZE` (25) y `HUD_SECONDARY_FONT_SIZE` (21), panel de carga más ancho (400) con filas de
dos renglones, tarjeta superior derecha más ancha. `test_hud_flow.gd` verifica el mínimo.

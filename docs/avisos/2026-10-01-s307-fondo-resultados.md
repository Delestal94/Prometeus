# La pantalla de resultados tiene ilustración de fondo (S-307)

**Fecha:** 2026-10-01 · **De:** Nacho (sesión de arte) · **Para:** Slatex

## Qué cambió

`scripts/ui/hud/hud.gd` (tu dominio):
- `_build_overlay_card()` crea `results_backdrop` (`TextureRect` "ResultsBackdrop", primer hijo de `overlay`, debajo
  de `overlay_center`) con `assets/ui/backgrounds/tx_ui_results_background_1920.png`, `STRETCH_KEEP_ASPECT_COVERED`,
  oscurecida con `modulate` `RESULTS_ART_TINT` (0,8).
- `overlay_mode` ahora tiene setter (`_set_overlay_mode`): con `"results"` muestra la ilustración y pone el overlay
  opaco; con cualquier otro modo la esconde y el overlay vuelve a `Color(UiTheme.BACKDROP, OVERLAY_DIM)` (0,72, el
  valor de siempre, ahora con nombre). Ninguna firma cambia; `hud_results.gd`, `hud_pause.gd` y `hud_newspaper.gd`
  no se tocaron.

`tests/test_hud_flow.gd` exige que se vea solo en resultados (entrega, endless y host perdido) y se apague en
inicio, pausa y desconexión.

## Qué tiene que hacer Slatex

Nada. Si agregás un modo nuevo al overlay, pasá por `overlay_mode` (no por `overlay.color`) y la ilustración se
apaga sola. En 4:3 la tarjeta tapa casi toda la ilustración: es el ancho de la tarjeta, no el fondo.

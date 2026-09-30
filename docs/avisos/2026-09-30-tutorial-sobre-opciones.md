# El tutorial de cuidado ya no se dibuja sobre Opciones (archivos de Slatex)

Bug visto en una captura con GPU: con el panel de Opciones abierto, la tarjeta "Cómo cuidar la carga"
(`scripts/ui/hud/care_practice.gd`) aparecía encima, a la derecha.

Causa: la tarjeta de cuidado y la de práctica se dibujan en un `CanvasLayer` propio con `layer = 7`
(`scripts/gameplay/player/player_cargo_care.gd`), mientras que el HUD con todos sus modales (Opciones, pausa,
resultados, depósito, tripulación) es el `CanvasLayer` 1.

Cambio: `player_cargo_care.gd` usa ahora `CARD_LAYER = 0`, debajo del HUD. Nada de `scripts/ui/` cambia.
Regla para el que agregue algo nuevo: lo que es del tablero va debajo de la capa del HUD o dentro de ella; un
`CanvasLayer` con número mayor que el del HUD tapa sus modales. Test: `tests/test_modal_layers.gd`.

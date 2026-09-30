# Aviso: N-223, menos trabajo por frame (2026-09-30)

Toca la zona compartida (`level_base.gd`) y un archivo de Slatex (`interaction/seat_point.gd`).

- `level_base.gd`: `route_progress_changed` y `delivery_status_changed` salen a ~8 Hz
  (`_emit_hud_signals`), no en cada tick de física. Un cambio de "en la zona" o de "quieto" sale en el
  mismo tick. `stopped_seconds`, `RunManager.current_distance` y el fin de partida del host siguen
  corriendo en cada tick. Los únicos que escuchan esas señales son `hud_cargo_panel._on_progress` y
  `hud_prompts._on_delivery` (el hint de 0,25 s sigue visible a 8 Hz).
- `seat_point.gd`: en vez de que cada asiento recorra el grupo `player` dos veces por frame, se hace
  una sola pasada por frame compartida por todos los asientos. `get_prompt` y `can_interact` siguen
  consultando en el momento. Se sacó `_local_player_seated_here`.
- `route.gd` / `route_streamer.gd` (Nacho): las búsquedas del punto más cercano del camino miran una
  ventana alrededor de la última y caen a la búsqueda completa si hace falta; la API no cambia.

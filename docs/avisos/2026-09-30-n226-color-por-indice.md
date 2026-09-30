# Aviso: N-226.2, el color sale del índice del anfitrión (2026-09-30)

Rama `ccr-7ed3ad6f-aszdmn`. Toca archivos de Slatex (`player.gd`, `player_voice.gd`, `scripts/ui/depot_panel.gd`,
`scripts/ui/hud/crew_panel.gd`, `hud_notices.gd`, `hud_results.gd`) y un test suyo (`test_crew_panel.gd`). No cambia
ninguna firma pública ni hay RPC nuevo. **Hace falta reimportar** (`godot --headless --import`) una vez: hay un
`class_name` nuevo, `PlayerColorSlot`.

## Qué cambió para Slatex

- **Un solo helper**: `PlayerColorSlot.slot(peer_id, palette_size) -> int` (`scripts/core/player_color_slot.gd`).
  Devuelve `posmod(NetworkManager.color_slot(peer_id), palette_size)`, con el host fijo en 0. Reemplaza
  `posmod(peer_id, 5)` / `peer_id % 5` en los seis lectores de color:
  - `player.gd` (`_apply_cosmetic`, y ahora escucha `color_slots_changed` para repintar si el mapa llega tarde) y
    `player_voice.gd` (el tono del grito);
  - `crew_panel.gd` (`shirt_color`; además se marca sucio con `color_slots_changed`), `hud_notices.gd` (`_speak`),
    `hud_results.gd` (puntos de los premios), `depot_panel.gd` (puntos de los votos; se reconstruye con
    `color_slots_changed` si la tienda está abierta).
  - Las paletas (`Player.PLAYER_COLORS`, `RESULT_PLAYER_COLORS`) no cambian. Si agregan un color, el helper ya
    recibe el tamaño; los índices 5..7 (salas de 6 a 8) se repiten sobre 0..2 mientras la paleta tenga 5.
- **Cambio visible**: jugando solo, el anfitrión (peer 1) pasa de amarillo a menta (slot 0, el mismo color que en
  una sala). Antes era amarillo solo y menta en sala; ahora siempre menta. `test_crew_panel.gd` esperaba
  `PLAYER_COLORS[1]` para el peer 1 y ahora espera `[0]`.
- **Nombre del jugador en los premios** (`hud_results.gd`, `tr("UI_PLAYER_N") % peer`): sigue mostrando el id de
  peer, que con ENet/Steam es un número enorme. No lo toqué (no es color); queda a criterio de Slatex usar el
  nombre del color (`CrewProgression.player_color_name(peer)`) como hace `crew_panel.gd`.

## Campaña (`crew_progression.gd`, de Nacho)

- `CAMPAIGN_VERSION` 1 → 2: `"players"` se guarda por slot (`"0"`..`"4"`), no por nombre de color. Un guardado
  versión 1 se migra al cargar (el anfitrión era siempre el peer 1, "yellow": pasa al slot 0, y "mint" al 1; los
  demás igual). Un archivo corrupto, de una versión más nueva o con campos de otro tipo no rompe: arranca de cero
  (con `push_warning`) o carga lo que pueda.
- El progreso de quien se va se guarda con el slot que tenía cuando cambió el roster (la red libera el slot antes
  de avisar), y el slot liberado lo hereda el siguiente que entra: el slot es el asiento en la tripulación.

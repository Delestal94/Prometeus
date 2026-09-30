# S-205 · Respuesta local al mantener y `--fake-lag` en el input de cuidado

Toca dominio de Slatex (`player/`, `package/`), sin cambiar firmas existentes.

- `scripts/gameplay/player/player_cargo_care.gd`: el input de cuidado (`submit_care_input` y
  `submit_tender_input`) sale ahora por `send_input()`, que primero avisa a `PlayerHoldFeedback` (el
  "estoy sosteniendo" local, el mismo frame) y después manda al host, con retraso si hay `--fake-lag`.
  `_physics_process` pasó a `_tick()` + `end_frame()` + `flush()`.
- `scripts/gameplay/player/player_hold_feedback.gd` (nuevo): flag local `holding`; nada lo replica ni
  lo lee el host.
- `scripts/gameplay/package/tender_input_lag.gd` (nuevo): `--fake-lag=<ms>` (y `--net-sim` en LAN),
  solo en build de debug, retrasa lo que el cliente manda al host.
- `scripts/gameplay/package/package_feedback.gd`: `set_local_grip(bool)` / `grip_glow()`, brillo cálido
  de la caja mientras el jugador local la sostiene (solo presentación).
- Test: `tests/test_local_hold_feedback.gd`.

Slatex: no hace falta hacer nada. Las manos del cuerpo sentado no reaccionan al sostener (no hay pose
de sostener hoy); queda para cuando se cierre S-311, leyendo `PlayerHoldFeedback.holding`.

Zona compartida (revisión de red, misma rama):
- `scripts/core/network_manager.gd` (solo el `print` de `--net-sim`), `scripts/core/net_stats.gd` (comentario),
  `README.md` y `docs/investigacion-red.md`: en LAN, `--net-sim` ahora también retrasa y descarta el input
  de cuidado del cliente, no solo las poses del camión.

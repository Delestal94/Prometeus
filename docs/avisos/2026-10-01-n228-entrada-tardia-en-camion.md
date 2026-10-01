# Quien entra con la partida en curso aparece sentado en el camión (archivos de Slatex)

N-228.7: con el camión ya en la ruta, el que se une (o vuelve tras una caída) aparecía en el depósito, lejos
de todos y sin forma de alcanzar al camión.

- `scripts/gameplay/late_join_seating.gd` (nuevo, `LateJoinSeating`, solo host): con
  `RunManager.is_running` y sin resultados, elige un asiento de pasajero libre del camión (grupo
  `cargo_seat`, filtrado con `can_interact`) y el jugador aparece en su `ExitPoint` y se sienta con
  `seat.interact()` justo después del `spawn()`. Preferencia: el asiento que mira más cajas sin cuidador;
  si no, uno que no le saque la caja a quien ya la cuida; si no, cualquiera libre. Sin asiento posible,
  aparece de pie en el pasillo de la caja de carga (`BAY_SPOT`, sin chocar con las cajas del estante).
  Antes de que arranque la entrega, y con resultados en pantalla, sigue apareciendo en el depósito.
- `scripts/gameplay/level_common.gd`: crea el nodo en `_ready` y lo usa en
  `_sync_players`.
- `scripts/gameplay/interaction/seat_point.gd` (de Slatex): dos consultas nuevas de host,
  `unminded_cargo()` y `would_displace()`. Nada existente cambió de firma.
- Los datos de spawn del jugador (`player_spawner.gd`, de Slatex) pueden traer `vehicle_position`: el punto
  de aparición en el espacio del camión, que cada peer resuelve contra su copia del camión (el cliente lo
  dibuja ~0.1 s atrás del host). Sube `PROTOCOL_VERSION` a 21 (20 lo usa el PR #145: `test_protocol_version`
  queda en rojo hasta que ese PR entre o se renumere uno de los dos). Con asiento, el host además escribe
  `seat_node_path` en su copia al sentarlo, para que no quede sólida en la ruta hasta que llegue
  `board_seat`. El orden spawn → `board_seat` lo garantiza Godot (el spawn sale por el canal 0 confiable
  antes de que `spawn()` vuelva).
- El slot de color al reconectarse ya lo conservaba N-221 (`test_network_rejoin`): no cambió.

Test: `test_late_join_seating` (nuevo; entrega y Endless).

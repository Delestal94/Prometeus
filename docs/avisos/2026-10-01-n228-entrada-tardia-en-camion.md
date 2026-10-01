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
- Sin RPC ni propiedades replicadas nuevas: `PROTOCOL_VERSION` sigue igual. El orden spawn → `board_seat`
  lo garantiza Godot (el spawn sale por el canal 0 confiable antes de que `spawn()` vuelva).
- El slot de color al reconectarse ya lo conservaba N-221 (`test_network_rejoin`): no cambió.

Test: `test_late_join_seating` (nuevo; entrega y Endless).

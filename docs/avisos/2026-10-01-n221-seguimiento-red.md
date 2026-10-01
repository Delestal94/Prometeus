# Aviso: N-221, seguimiento de la auditoría de red de #125 (2026-10-01)

Rama `nacho/N-221-followups`. **Cambia el protocolo**: `NetworkManager.PROTOCOL_VERSION` pasa de 17 a 18
(el handshake y `_sync_color_slots` llevan los slots de los que se fueron; con la sala llena la admisión se
decide con la respuesta "listo"; `_report_level_ready` solo cuenta un reporte que el host debe). Un cliente
viejo con un host nuevo recibe "otra versión" al conectarse: actualicen los dos.
**Ninguna firma pública cambia de forma incompatible**: se agregan una clase, una señal, funciones y
constantes; `_sync_color_slots` suma un segundo argumento opcional.

## Qué cambió

**Módulo `net_session` (zona compartida):**
- `NetSession`: señal nueva `peer_removed(peer_id)`, en todos los peers, una vez por salida, después de
  `_peer_left` y antes de `roster_changed`; también para un fantasma cuando se lo suelta (`drop_peer()`), y no
  de nuevo cuando su conexión se cierra 0,5-2 s después. **Lo que un jugador que se va tenía (caja, asiento,
  voto) escucha esta señal, no `multiplayer.peer_disconnected`.**
- Nueva `modules/net_session/net_admission.gd` (`NetAdmission`): quién entra a la sala. Un lugar entre
  `max_players` contando a los que todavía autentican, más el del juego (`_admit_peer`). Con la sala llena, el
  que vuelve antes de que el host note su caída recupera el lugar de su fantasma; en Steam se sabe quién es al
  autenticar, en LAN con su respuesta de listo (carga el nivel "sin lugar" y ahí se decide); un extraño oye
  `"full"`. `_identify_peer` delega en `NetAdmission.identify()` (misma conducta).
- ENet: `create_server(port, max_players)` (antes `max_players - 1`): una conexión de más para ese caso.
- `_report_level_ready` ya no gasta cupo de `RpcGuard` (perderlo dejaba el nivel del cliente sin jugadores);
  solo hace algo si el host debe ese reporte (`_reloads_owed`).
- `_settle_now` no le devuelve el timeout de sesión (20 s) a un fantasma ya soltado.
- `RpcGuard`: `allow_critical_request(node)` / `take_critical_request(peer, msec)` (con el cupo gastado, una
  reserva de `CRITICAL_RESERVE` = 10 que se repone a `CRITICAL_PER_SECOND` = 5), `name_ok(StringName)` y
  `path_ok(NodePath)` (`MAX_PATH_LENGTH` = 256). `NetPeerIdentities.peer_of(identity)`.
- `NetEventBus.request()`: `name_ok(event_name)`.

**Otros módulos (zona compartida):** `SeatPoint.release_occupant` usa `allow_critical_request`;
`CoopVote.request_vote` chequea `name_ok(offer_id)`.

**Juego, zona compartida:**
- `network_manager.gd`: `PROTOCOL_VERSION` 18 (línea `## 18:` en el historial; el 17 lo tomó N-228.4, #139). `_session_state()` suma
  `"departed"` y `_sync_color_slots(slots, departed = {})` también: el que entra tarde ve el mismo color que los
  demás para los que se fueron antes. `_apply_departed_slots()`; `ColorSlots.is_valid_departed()`. La reserva
  de slot que tomó un joiner que no llegó a entrar, o que resultó ser otro que volvía a su propio slot, vuelve a
  su dueño (`_borrowed_reservations`). Función nueva `slot_kept_for(peer_id)`.
- `crew_progression.gd`: el recién llegado que toma el slot reservado de otro ya no pisa su entrada de campaña;
  se aparta (`_displaced_players`) y se le devuelve si vuelve (sigue a `peer_rejoined`).
- `shop_vote_manager.gd`, `depot.gd`: `name_ok` en `request_discount`, `request_supply`,
  `request_discounted_supply`.

**Archivos de Slatex (sin cambios de firma, nada que hacer):**
- `scripts/gameplay/package/package.gd`: conecta `peer_left` a `NetworkManager.peer_removed` (en `_enter_tree`,
  junto a `peer_level_ready`) en lugar de `multiplayer.peer_disconnected` en `_ready`: con la conexión vieja de
  un jugador que volvió, la caja perdía el `hold_crisis` porque la desconexión llegaba cuando su jugador ya la
  había soltado. `request_drop` usa `allow_critical_request`; `request_transfer` chequea `path_ok`.
- `scripts/gameplay/package/package_rescue.gd`: `peer_left` no hace nada fuera del host (ahora lo oyen todos).
- `scripts/gameplay/player/player.gd`: solo un comentario (con más de cinco, los slots 5..7 repiten color).

## Tests

`test_network_rejoin` (fantasma con caja en crisis; sala de ocho con fantasma; entrada desplazada; reservas
que vuelven), `test_network_roster` (slots de los que se fueron en el handshake), `test_rpc_guard` (regla para
`StringName`/`NodePath`, `CRITICAL_RPCS`, `BUDGET_EXEMPT`), `net_session__test_rpc_guard` (reserva crítica,
`name_ok`, `path_ok`), `net_session__test_net_session_rejoin` (`peer_removed`, `NetAdmission`, y una sala de dos
por ENet en un proceso: el que vuelve con su fantasma todavía conectado entra, un extraño oye "full"), y una
etapa nueva al final de `tests/net_pair.gd`: el cliente deja su conexión abierta sin sondear (cable
desenchufado) con una caja en crisis, vuelve, y el host le sostiene la ventana de rescate. `tools/run-net-pair.sh`
pasa de 150 a 240 s por proceso (una carga de nivel más en el cliente).

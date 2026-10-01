# Aviso: N-221, seguimiento de la auditoría de red de #125 (2026-10-01)

Rama `nacho/N-221-followups`. **Cambia el protocolo**: `NetworkManager.PROTOCOL_VERSION` pasa de 19 a 20
(el handshake y `_sync_color_slots` llevan los slots de los que se fueron; con la sala llena la admisión se
decide con la respuesta "listo"; `_report_level_ready` solo cuenta un reporte que el host debe; en LAN la
identidad de la respuesta "listo" es un eslabón de una cadena de hashes). Un cliente viejo con un host nuevo
recibe "otra versión" al conectarse: actualicen los dos.
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
  `"full"` antes de que se mueva nada (ni `peer_rejoined` ni `_peer_returned`). `_identify_peer` delega en
  `NetAdmission.identify()`.
- **Identidad en LAN, cadena de hashes (Lamport):** la respuesta "listo" ya no lleva siempre el mismo
  `sha256(token + nonce)`, que cualquiera que escuchara la LAN podía repetir para quedarse con el lugar y el
  mérito de otro. Ahora el que entra manda `H^64(raíz)` la primera vez y un eslabón antes en cada vuelta
  (`H^(64-k)`), con `raíz = sha256(token + nonce + cadena)`; el host lo acepta si al hashearlo hacia adelante
  (1 a 64 veces) llega al último que guardó, y guarda el nuevo. Un valor ya visto (el último o uno anterior de
  la cadena) se rechaza con `"connection"` y el peer vivo sigue. Acepta saltar eslabones porque un intento que
  el host rechazó antes de anotar (sala llena) ya gastó uno. Agotados los 64 de una sesión, empieza una cadena
  nueva y el host lo ve como alguien nuevo. Steam no cambia (el Steam ID lo garantiza Valve).
  `NetPeerIdentities`: `CHAIN_LENGTH`, `chain_link()`, `known_as()`, `is_replay()`; `peer_of()` y `record()`
  siguen la cadena.
- **Rechazos:** el host le manda la falla al que no entra (`"full"`, `"version"`, `"connection"`) y, si no se va
  solo, lo corta 0,5 s después (`NetAdmission.refuse()`): antes ocupaba el lugar de sobra del transporte hasta
  45 s. No es en el mismo frame porque cortar un enlace ENet descarta lo que todavía no tuvo ack
  (`enet_peer_reset_queues`), y la falla se perdería.
- **El fantasma se suelta del todo en el acto:** `NetAdmission.close_dropped()` (antes `_close_connection`) usa
  `SceneMultiplayer.disconnect_peer()`, que en Godot 4.7.2 hace `_del_peer` al momento (limpia replicador y caché,
  manda `DEL_PEER` a los otros clientes) con las señales bloqueadas: no hay `peer_disconnected` para el fantasma
  (el roster ya lo soltó con `peer_removed`). Se acabaron los "Unable to send packet… max channels: 0" y el
  fantasma visible en los clientes durante 0,5-2 s. `run-net-pair.sh` falla si vuelven a aparecer.
- **Reinicio con un fantasma cerrándose:** `announce_restart()` y el reinicio en `level_ready()` recorren
  `peer_ids` con el enlace arriba (`_linked_clients()`), no `multiplayer.get_peers()`: antes le ponían 45 s al
  fantasma y le debían una recarga. `_on_peer_disconnected` de una conexión ya soltada borra también sus
  `_enet_timeouts` y `_reloads_owed`.
- ENet: `create_server(port, max_players)` (antes `max_players - 1`): una conexión de más para ese caso.
- `_report_level_ready` ya no gasta cupo de `RpcGuard` (perderlo dejaba el nivel del cliente sin jugadores);
  solo hace algo si el host debe ese reporte (`_reloads_owed`).
- `_settle_now` no le devuelve el timeout de sesión (20 s) a un fantasma ya soltado.
- `RpcGuard`: `allow_critical_request(node)` / `take_critical_request(peer, msec)` (con el cupo gastado, una
  reserva de `CRITICAL_RESERVE` = 10 que se repone a `CRITICAL_PER_SECOND` = 5), `name_ok(StringName)` y
  `path_ok(NodePath)` (`MAX_PATH_LENGTH` = 256).
- `NetEventBus.request()`: `name_ok(event_name)`.

**Otros módulos (zona compartida):** `SeatPoint.release_occupant` usa `allow_critical_request`;
`CoopVote.request_vote` chequea `name_ok(offer_id)`.

**Juego, zona compartida:**
- `network_manager.gd`: `PROTOCOL_VERSION` 20 (línea `## 20:` en el historial; el 17, el 18 y el 19 los tomaron N-228.4, #139, N-228.8, #142, y N-228.5, #144). `_session_state()` suma
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
por ENet en un proceso: un fantasma soltado sale de `SceneMultiplayer` en un frame y un reinicio en ese frame
no lo espera ni le debe nada; el que vuelve con su fantasma todavía conectado entra; el que repite su identidad
oye "connection"; un extraño que ignora "full" queda cortado en menos de un segundo; repeticiones del último
eslabón o de uno anterior, rechazadas, y el siguiente de verdad aceptado), `test_network_rejoin` también: el que
vuelve a una sala llena sin fantasma oye "full" sin que se le mueva el mérito. Y una etapa nueva al final de
`tests/net_pair.gd`: el cliente deja su conexión abierta sin sondear (cable desenchufado) con una caja en
crisis, vuelve, y el host le sostiene la ventana de rescate y suelta al fantasma en el acto.
`tools/run-net-pair.sh` pasa de 150 a 240 s por proceso (una carga de nivel más en el cliente) y falla si un log
tiene "Unable to send packet".

## Pendiente

Pedir la identidad antes de mandar el estado completo, para que nadie cargue el nivel solo para oír "full"
(hoy en LAN un extraño a una sala llena carga el nivel antes del rechazo): subtarea en N-221.

# Aviso: N-221, validación de RPC y reconexión (con N-226.2, colores y campaña por slot) (2026-09-30)

Rama `nacho/N-221-rpc-guard-rejoin`, rebasada sobre `main` con los colores por slot de N-226.1 (`ColorSlots`,
`NetworkManager.color_slot()`) y los módulos portables. **Cambia el protocolo**: `NetworkManager.PROTOCOL_VERSION`
pasa de 11 a 12 (el handshake lleva un nonce de sesión, la respuesta "ready" una identidad y la campaña viaja por
slot). Un cliente viejo con un host nuevo recibe "otra versión" al conectarse: actualicen los dos.
**Ninguna firma pública cambia**: se agregan clases, funciones, señales, hooks y constantes. Ningún RPC nuevo ni
renombrado; varios RPC existentes ahora descartan lo que no pasa el chequeo.

## Qué cambió

**Módulo `net_session` (zona compartida):**
- Nuevo `modules/net_session/rpc_guard.gd` (`RpcGuard`, estático): `sender_ok(node[, peer])`, `from_host(node)`,
  `allow_request(node)` (cupo por peer para pedidos confiables: 40 de golpe, 20 por segundo; las llamadas del host
  no gastan), `finite_float/vec2/vec3/transform()`, `dict_ok(d, max_keys)`, `args_ok(a, max_size)`, `text_ok(s)`,
  `plain_value(v)`. Lo que no pasa se ignora en silencio (el cupo avisa una vez por peer con `push_warning`).
- `NetSession`: señal nueva `peer_rejoined(old_id, new_id)`, `peer_identity(peer_id)`, `drop_peer(id)` y el hook
  `_peer_returned(id, previous_id)`. El handshake suma la clave `"session"` (nonce; ahora hay tres claves
  reservadas: `version`, `scene`, `session`) y la respuesta "ready" suma `"identity"` (en LAN un `sha256` del token
  del proceso con ese nonce, nunca el token; en Steam el host usa el Steam ID). Si vuelve alguien con la misma
  identidad, el juego le devuelve lo suyo (`_peer_returned`) y sale `peer_rejoined`; si su conexión vieja seguía
  arriba, se cae como fantasma: sale del roster como cualquier salida (`_peer_left`, `roster_changed`: el nivel
  suelta su jugador, su caja y su asiento) y el transporte la cierra con timeout corto. `_report_level_ready` gasta
  del cupo. Al irse un peer se olvidan su identidad y su cupo; la memoria de identidades de los que se fueron es
  acotada (`IDENTITY_MEMORY`).
- `NetEventBus.request()` era un RPC `any_peer` que relayaba **cualquier** evento: ahora solo los que figuran en
  `request_cooldowns` (0 = sin límite), con argumentos planos (`RpcGuard.args_ok`) y con cupo.
- `SteamVoice._receive_voice`: `sender_ok`.
- `interaction` (`Interactable.request_interact`, `SeatPoint.release_occupant`) y `coop_vote` (`request_open`,
  `request_vote`): cupo. `interaction/module.cfg` pasa a depender de `net_session`.

**Zona compartida del juego:**
- `network_manager.gd`: `PROTOCOL_VERSION` 12 (con la regla en el comentario). **En sala el host vuelve a ser el
  slot 1 (amarillo)**, como jugando solo: N-226.1 lo había puesto en 0 (menta), pero el guardarropa (`team_color`)
  y la vista previa de la cara muestran la remera propia amarilla, y así el dueño del guardado tiene un solo color y
  una sola entrada en la campaña. Los que entran toman el libre más bajo: 0, 2, 3… El slot del que se
  va queda reservado para él mientras haya otros libres (`_slot_reservations`) y vuelve a ser suyo al reconectarse;
  con la sala llena lo toma el que entra, que arranca sin el mérito ni la carta de ese slot
  (`inherits_color_slot(peer_id)`, nueva). El que se fue sigue leyendo su último slot (`_departed_slots`, para los
  resultados y para que la campaña lo guarde en su lugar). `_fail` ahora anuncia el mapa vacío
  (`color_slots_changed` sale desde `_reset_session_state`).
- `color_slots.gd`: `HOST_ID`, `HOST_SLOT` (1), `place_host()` y `assign_avoiding()` (nuevas); `slot_of()` da
  `HOST_SLOT` al host sin mapa (lo mismo que `posmod(1, n)` de antes).
- `event_bus.gd`: `request_cooldowns` lista `ping_sent` y `horn_honked`; `_accept_request` chequea su forma;
  `request_ping` descarta posiciones no finitas y etiquetas de más de 64 caracteres.
- `run_manager.gd`: `_request_delivery_photo` gasta del cupo.

**Libres y de Nacho:** `crew_progression.gd` — campaña **versión 2**: mérito, carta y entregas secas por slot
(`"0".."7"`), no por nombre de color; un archivo versión 1 se migra al cargar por el índice del color (el amarillo
del host sigue siendo el 1). `player_color_key/name` y `player_slot()` (nueva) salen de `color_slot()`; `_on_peer_rejoined` pasa el
mérito de la partida en curso al id nuevo; `request_use_card` con cupo; `_receive_campaign` comparte canal con
`_sync_color_slots` (lo mira `test_rpc_guard`). `shop_vote_manager.gd` (`request_revote`, `request_discount`),
`depot.gd` (`request_supply`, `request_discounted_supply`), `rail_crossing_segment.gd` (`_request_state`): cupo.
`vehicle.gd`: el volante descarta `NaN`/`inf` (`clampf()` los dejaba pasar). `unlock_manager.gd`: un comentario.

**Archivos de Slatex:**
- `player.gd` (sigue en 1000 líneas): el color del traje sale de `PlayerAppearance.crew_slot(self)` y se vuelve a
  aplicar con `color_slots_changed` (`PlayerAppearance.follow_crew_slot(self)` en `_ready`). `_from_host()` usa
  `RpcGuard.from_host()`; `receive_package_hit` descarta empujes no finitos.
- `player_appearance.gd`: `crew_slot(player)` y `follow_crew_slot(player)` (nuevas, estáticas).
- `player_voice.gd`: el tono sale del slot, preguntado en cada línea.
- `player_sprint.gd`: `submit_run_step` con cupo; `play_stumble` usa `RpcGuard.from_host()`.
- `package.gd`: `request_set_open`, `request_assist`, `request_stop_assist`, `request_transfer`, `request_drop` y
  `request_lap_toggle` gastan del cupo; `submit_carry_transform` y `request_drop` descartan poses no finitas o
  aplastadas (`finite_transform`); `submit_tender_input` y `submit_care_input` descartan diccionarios de más de 16
  claves o con valores que no son simples (`dict_ok`; los reales tienen 8).
- `scripts/ui/`: `hud_notices.gd`, `hud_results.gd`, `depot_panel.gd` y `crew_panel.gd` leen
  `posmod(NetworkManager.color_slot(id), paleta.size())`; `crew_panel.gd` también se refresca con
  `color_slots_changed`.

**Tests:** nuevos `test_rpc_guard` (recorre los 36 `any_peer`, módulos incluidos), `net_session__test_rpc_guard`,
`net_session__test_net_session_rejoin`, `test_network_rejoin`, `test_crew_color_slots`; `net_pair` suma la
reconexión real y `net_trio` compara `slots=` en los tres procesos. Cambian expectativas en `test_network_roster`
(el host 1 y los que entran 0, 2, 3, 4; el que se fue lee su último slot) y `test_crew_campaign_save` (versión 2
y migración).

## Qué tiene que hacer Slatex

- `git pull` antes de seguir con `player.gd`, `package.gd`, `player_sprint.gd` o el HUD.
- Jugando solo nada cambia de color. En sala el host vuelve a amarillo y el primero que entra usa menta.
- Un RPC `any_peer` nuevo pasa por `RpcGuard` (regla en `convenciones-godot.md` §0.2): si no, `test_rpc_guard`
  falla y dice qué falta. Si cambia un RPC o lo que se replica, subí `PROTOCOL_VERSION`.
- El color de un jugador es `NetworkManager.color_slot(peer_id)` (en `player/`, `PlayerAppearance.crew_slot()`),
  leído con `posmod(..., paleta.size())`; nunca `peer_id % 5`. Si guardás el color en algún lado, escuchá
  `color_slots_changed`.

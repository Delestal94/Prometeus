# Protocolo 57: cada jugador y cada caja dicen en qué vehículo van (D-0302.2.b.4.b)

**Fecha:** 2026-10-22 · **De:** Nacho (red) · **Para:** Slatex

## Qué cambió

- **`PROTOCOL_VERSION` 57** (`scripts/core/network_manager.gd`, zona compartida): solo la constante y su línea del
  historial. Ninguna firma de `NetworkManager`, `NetSession` o `EventBus` cambió.
  **Cambió el protocolo:** un cliente viejo con un host nuevo no se entiende (las propiedades de los sincronizadores y
  los argumentos de dos RPC de la caja son otros).
- **`player.tscn` y `package.tscn`**: el `MultiplayerSynchronizer` replica una propiedad nueva al final,
  `net_vehicle` (`int`, `REPLICATION_MODE_ALWAYS`, en el estado de spawn): en qué vehículo está el espacio de
  `net_position` / `net_transform` (`VehiclePick.index_of()`: el lugar del vehículo en el grupo `vehicle` en orden de
  árbol, el mismo en todos los peers; -1 a pie o suelta). Viaja en el mismo paquete que la pose (2 bytes más por
  paquete). El `NetRestThrottle` de la caja también mira `net_vehicle`.
- **`player.gd`** (`var net_vehicle: int = -1`; el comentario de `net_position` quedó en 3 líneas para no pasar las
  700) y **`player_ride.gd`**: `publish_net_state()` escribe `net_vehicle` junto a `net_in_vehicle`;
  `find_vehicle()` en la copia de otro peer, con más de un vehículo, toma el que nombra el dueño
  (`VehiclePick.told()`) en vez del primero del grupo. Con un solo vehículo no cambia nada.
- **`package.gd`**: `var net_vehicle`, `_publish_net_state()` lo escribe, `_find_vehicle()` en una copia toma el que
  nombra el host. **Firmas (RPC, solo se agregó un argumento opcional al final):**
  `submit_carry_transform(carry, in_vehicle := false, in_hands := Transform3D(), vehicle := -1)` (el primer argumento
  se renombró de `carry_transform` a `carry` para que la firma entre en una línea de 120: `test_rpc_guard` la lee así;
  por posición es el mismo) y `request_drop(drop_transform, in_vehicle := false, vehicle := -1)`. Mismo modo, canal y
  `reliable` que antes. `predict_carry(carry_transform, in_vehicle, vehicle: Node3D = null)` (local, no RPC) guarda el
  vehículo del que carga.
- **`package_handling.gd`**: `accept_carry(..., vehicle_index := -1)` y `drop(..., vehicle_index := -1)` ponen la
  pose del que carga en el vehículo que nombra (`space_of()`, nueva), que pasa a ser el de la caja. Antes el host la
  ponía en el vehículo de la caja: entrando de espaldas a la segunda camioneta con una caja, la caja saltaba a la
  primera y se quedaba ahí.
- **`package_net_pose.gd`**: la caja que el cliente predice en sus manos se dibuja en el vehículo del que carga
  (`_predicted_vehicle`), no en el que el host todavía no le asignó.
- **`player_carry.gd`**: manda el índice del vehículo con `submit_carry_transform` y `request_drop`, y se lo pasa a
  `predict_carry`.
- **`scripts/gameplay/vehicle/vehicle_pick.gd`**: `listed()`, `index_of()`, `at()` y `told()` (la lista se arma una
  vez por frame mientras el grupo no cambie de tamaño).
- Tests: `test_company_multi_vehicle` (copias de jugador y caja en la segunda camioneta, carga y suelta en el host,
  predicción del que carga, un solo vehículo igual que antes), `test_ride_sync` y `test_player_split`
  (`net_vehicle` en la lista).

## Qué tiene que hacer Slatex

Nada obligatorio. Si tocás `player/` o `package/`: lo que publique una pose en el espacio de un vehículo tiene que
publicar también cuál (`net_vehicle`, `VehiclePick.index_of()`), y lo que la lea en otro peer, buscarlo con
`VehiclePick.told()` / `at()`. Los `get_first_node_in_group(&"vehicle")` de HUD, asiento, cuidado de carga, voz y
fauna siguen igual (ver `docs/expansion-distritos/revisar/D-0302.2.b.4.b.md`). Si una rama tuya sube
`PROTOCOL_VERSION`, la próxima libre es 55.

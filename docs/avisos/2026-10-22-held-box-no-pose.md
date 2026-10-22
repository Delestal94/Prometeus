# D-2002.5: la caja en la mano de alguien a pie no manda su pose (protocolo 60)

Tocado en archivos del dominio de Slatex (`package/`, `player/`), en zona compartida (`network_manager.gd`,
`modules/net_pose_smoother/`) y en tests. **Cambia el protocolo:** `PROTOCOL_VERSION` 59 -> 60 (se tomó primero 55 y se
renumeró al mezclar `main`, que ya tenía 55-59: D-0151.3b, D-0621.b, D-0302.2.b.4.b, D-0307.1 y D-0910.2, `docs/convenciones-godot.md`
§6.3). Un cliente con 59 y un host con 60 no se conectan (error de versión en el menú); con el mismo número se desincronizarían en silencio (la configuración
de replicación de la caja y la firma de un RPC son distintas). Decisión:
[`decisiones/2026-10-22-caja-en-la-mano-sin-pose.md`](../decisiones/2026-10-22-caja-en-la-mano-sin-pose.md).

Vale para todos los modos (Reparto, Infinito y Empresa): es el mismo `package.tscn`.

- `scenes/gameplay/package/package.tscn` (Slatex): sale `hold_offset` de la replicación (era `properties/20`,
  `ALWAYS`) y de los `watched` del `NetRestThrottle`; `net_vehicle` (D-0302.2.b.4.b) pasa de `properties/21` a
  `properties/20` (SceneReplicationConfig no admite huecos en la numeración). La pose de cada caja pasa de 155 a 103
  B por envío (sin `net_vehicle`, de 150 a 98).
- `scripts/gameplay/package/package.gd` (Slatex): se va la variable `hold_offset`. `submit_carry_transform` pierde
  su tercer argumento (`in_hands`): **cambió la firma de un RPC** (ahora `(carry, in_vehicle := false, vehicle :=
  -1)`, el índice de vehículo de D-0302.2.b.4.b queda tercero; sigue `any_peer`, `call_local`, `unreliable_ordered`,
  canal 0; `test_package_split` no cambia porque mira modo y canal; `test_company_multi_vehicle` lo llama sin el
  `Transform3D()` del medio). `_publish_net_state()` (host, cada tick) mutea el `NetRestThrottle` de la caja mientras
  `PackageNetPose.muted(self)`: `is_held` y `carrier_peer_id > 0` (la tiene en la mano un `Player` a pie). Muteada
  manda su pose cada 5 s (`NetRestThrottle.muted_interval`); al soltarla, a ritmo completo desde el tick siguiente.
  Nueva variable `_rest_throttle`.
- `scripts/gameplay/package/package_handling.gd` (Slatex): `accept_carry(p, sender, carry_transform, in_vehicle,
  vehicle_index = -1)` sin `in_hands`; `carrier_peer_id` se pone solo si el que la lleva es un `Player` a pie (antes también cualquier
  nodo que no fuera `Player`). `set_held()` ya no toca `hold_offset`.
- `scripts/gameplay/package/package_net_pose.gd` (Slatex): `follow()` dibuja la caja donde la sostiene la copia
  local del jugador (`PlayerCarry.hands_pose()`, puesta en el cuerpo como se dibuja); `remote_carrier()` devuelve
  `Player` (solo de la misma sesión, y no si esa copia ya está sentada). Nueva `static muted(p)`. Las poses que
  llegan mientras está muteada no entran al buffer, y al soltarla la caja queda donde se dibujó (en el espacio del
  vehículo en que iban las manos: el del que la llevaba, no el `net_vehicle` de la caja, viejo mientras está
  muteada) hasta la primera
  pose nueva del host y después se acerca en `DROP_BLEND_SECONDS` (antes solo lo hacía el cliente del que la
  llevaba). Si la camioneta la lleva en la caja de carga, ese "donde se dibujó" va en el espacio de la camioneta
  (sigue andando con ella), y el acercamiento parte de ahí. En el cliente del que la lleva, si deja de predecir
  pero la sigue teniendo (un menú abierto: `update_carried_package()` no corre), se dibuja en sus manos con
  `hands_pose()`. Se fueron `MAX_HOLD_REACH` y `_was_predicted` (ahora `_was_in_hands`).
- `scripts/gameplay/player/player_carry.gd` (Slatex): nueva `hands_pose(package) -> Transform3D` (lo que antes
  armaba `update_carried_package()` adentro: punto de agarre bajo la cámara, el rayo contra lo que estorba, la
  subida de 1,3 s, la falda sentado); la usan el dueño y las copias de los demás. Una copia que nunca recibió una
  pose de la caja (join tardío, al que el host le repite `pick_up`) no hace la subida. `carry_position()` acepta la
  caja como argumento opcional.
- `modules/net_pose_smoother/net_rest_throttle.gd` (compartido): nuevas `set_muted(bool)`, `is_muted()` y
  `@export muted_interval` (5 s) y `MUTED_SHOW_FRAMES` (2). Muteado, manda cada `muted_interval` se mueva o no;
  mostrarlo a un peer (también un pulso de keepalive con `QUIET_META`) lo pone a cada tick por 2 frames y vuelve a
  muteado, para que ese peer reciba una pose enseguida; al desmutear vuelve a cada tick en el mismo tick y queda una
  ventana de `settle_seconds`.
- `scripts/core/network_manager.gd` (compartido): solo `PROTOCOL_VERSION` y su línea `## 60`.

Para Slatex: nada que hacer si no tocás el carry. Si cambiás dónde se sostiene la caja, cambialo en
`PlayerCarry.hands_pose()`: lo dibujan igual el dueño y los demás. Un componente nuevo que mueva la caja en la mano
de alguien a pie no puede contar con que el host mande su pose (llega cada 5 s); lo que necesite verse en los demás
tiene que salir de la pose del jugador. Tests: `test_remote_carry_alignment` (reescrito), `test_net_rest_throttle`,
`test_net_bandwidth_budget`, `test_company_bandwidth_budget`.

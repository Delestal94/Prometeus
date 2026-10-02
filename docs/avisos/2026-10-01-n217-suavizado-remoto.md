# Jugadores y cajas remotas suavizados, y sync a 30 Hz (N-217)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

- `scenes/gameplay/player/player.tscn`: el `MultiplayerSynchronizer` manda a 1/30 s (antes 1/60), replica
  `net_yaw` en vez de `rotation` y suma `net_time` como **última** propiedad. `PROTOCOL_VERSION` 22.
- `scripts/gameplay/player/player.gd` (tu dominio): variables nuevas `net_yaw`, `net_time` (con setter) y
  `_net_smoother`. El comentario largo de las medidas de los asientos pasó de `_seat_body_offset()` a
  `player_seat_pose.gd seat_body_offset()` (para que `player.gd` siga bajo 700 líneas). Ninguna firma cambió.
- `scripts/gameplay/player/player_ride.gd`: `publish_net_state()` también publica `net_yaw` y `net_time`;
  `apply_net_state()` dibuja al jugador remoto desde el buffer (`NetPoseSmoother`), un poco en el pasado e
  interpolado; nuevas `push_net_pose()`, `latest_position()` y `yaw_of()`.
- `scripts/gameplay/player/player_seat_pose.gd` `reach_origin()`: en el host, un jugador remoto a pie alcanza
  desde su pose más nueva, no desde la dibujada.
- `scenes/gameplay/package/package.tscn`: 1/30 s y `net_time` como última propiedad.
- `scripts/gameplay/package/package.gd` (tu dominio): `net_time` (el host la pone en `_publish_net_state()`),
  `_push_net_pose()` y `_net_smoother`; en el cliente `_process()` dibuja la caja desde el buffer salvo
  mientras la predice en las manos del que la lleva. Nueva `reach_slack(peer_id)`.
- `package_handling.gd transfer()`, `package_tending.gd _peer_within_assist_reach()`, `package.gd
  _peer_within_reach()` y `modules/interaction/interactable.gd _within_reach()`: suman
  `NetStats.reach_slack()` (5 m/s × ida y vuelta del que pide, tope 1,5 m; 0 sin red).
- `modules/net_pose_smoother/net_pose_smoother.gd` (zona compartida): colchón adaptativo (`delay()` en vez
  de la constante `DELAY`, que ya no existe), poses `local`, `latest_pose()`, `clock_ms()`, `local_now()`.

## Qué tiene que hacer Slatex

- Si agregás una propiedad al sync del jugador o de la caja, ponela **antes** de `net_time`: el setter de
  `net_time` es el que guarda la pose y tiene que llegar último (`test_remote_pose_smoothing` lo exige).
- Para girar a un jugador remoto no uses `rotation` replicada: el dueño publica `net_yaw` y el resto lo
  dibuja desde el buffer.
- Si alguien usaba `NetPoseSmoother.DELAY`, ahora es `smoother.delay()`.

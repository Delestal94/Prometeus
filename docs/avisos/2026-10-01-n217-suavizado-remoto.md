# Jugadores y cajas remotas suavizados, y sync a 30 Hz (N-217)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

- `scenes/gameplay/player/player.tscn`: el `MultiplayerSynchronizer` manda a 1/30 s (antes 1/60), replica
  `net_yaw` (relativo al rumbo del camión si viaja) en vez de `rotation` y suma `net_time`. Las copias
  remotas guardan cada pose al recibir el paquete entero (señal `synchronized`). `PROTOCOL_VERSION` 24.
- `scripts/gameplay/player/player.gd` (tu dominio): variables nuevas `net_yaw`, `net_time` y `_net_smoother`;
  en `_process` el jugador remoto se ubica **antes** de `animator.animate()`, porque la cabeza,
  `locomotion_speed` y `jump_anim_time` ahora salen del buffer, del mismo instante que el cuerpo. El comentario largo de las medidas de los asientos pasó de `_seat_body_offset()` a
  `player_seat_pose.gd seat_body_offset()` (para que `player.gd` siga bajo 700 líneas). Ninguna firma cambió.
- `scripts/gameplay/player/player_ride.gd`: `publish_net_state()` también publica `net_yaw` y `net_time`;
  `apply_net_state()` dibuja al jugador remoto desde el buffer (`NetPoseSmoother`), un poco en el pasado e
  interpolado; nuevas `push_net_pose()`, `latest_position()` y `yaw_of()`.
- `scripts/gameplay/player/player_seat_pose.gd` `reach_origin()`: en el host, un jugador remoto a pie alcanza
  desde su pose más nueva, no desde la dibujada.
- `scenes/gameplay/package/package.tscn`: 1/30 s, `net_time`, `carrier_peer_id` (on change) y `hold_offset`;
  `NetRestThrottle` también mira esas dos.
- `scripts/gameplay/package/package.gd` (tu dominio): `net_time`, `carrier_peer_id`, `hold_offset` y
  `_net_view` (nuevo `package_net_pose.gd`, `PackageNetPose`), que dibuja la caja en todos los peers:
  desde el buffer en el cliente; en las manos de un jugador remoto a pie, sobre su cuerpo como se lo dibuja
  (también en el host, que la sigue simulando en la pose de carga más nueva: `_physics_process` la
  reaplica en cada tick); y al terminar la predicción del que la llevaba, la diferencia se borra en 0,25 s.
  `submit_carry_transform` suma un tercer argumento, `in_hands` (la pose en el espacio del cuerpo, la
  manda `player_carry.gd`). Nueva `reach_slack(peer_id)`.
- `package_handling.gd`: `accept_carry()` recibe `in_hands` y pone `carrier_peer_id`/`hold_offset` si el que
  la lleva va a pie; `set_held()` los limpia y arranca `_carry_pose` donde está la caja.
- `package_handling.gd transfer()`, `package_tending.gd _peer_within_assist_reach()`, `package.gd
  _peer_within_reach()` y `modules/interaction/interactable.gd _within_reach()`: suman
  `NetStats.reach_slack()` (5 m/s × ida y vuelta del que pide, tope 1,5 m; 0 sin red).
- `modules/net_pose_smoother/net_pose_smoother.gd` (zona compartida): colchón adaptativo (`delay()` en vez
  de la constante `DELAY`, que ya no existe), poses `local`, `latest_pose()`, `clock_ms()`, `local_now()`.

- **El camión también cambió:** su suavizado usa el colchón adaptativo; en una LAN tranquila se dibuja
  ~50 ms en el pasado en vez de 100 ms fijos (`vehicle.gd _commit_net_pose()/_process()`).
- **A vigilar:** en el host, los jugadores remotos se dibujan (y chocan) en su pose de hace 50-200 ms.
  Los chequeos de alcance usan la pose más nueva, pero las colisiones físicas del host con un cuerpo remoto
  (empujar una caja suelta, por ejemplo) van atrasadas ese tiempo.

## Qué tiene que hacer Slatex

- Si un sistema tuyo mueve una caja en manos de alguien, tené en cuenta que en los otros peers se dibuja
  sobre el cuerpo del que la lleva (`PackageNetPose.follow`), no donde la simula el host.
- Para girar a un jugador remoto no uses `rotation` replicada: el dueño publica `net_yaw` y el resto lo
  dibuja desde el buffer.
- Si alguien usaba `NetPoseSmoother.DELAY`, ahora es `smoother.delay()`.

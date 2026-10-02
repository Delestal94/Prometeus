# Quien entra tarde ve qué caja lleva cada uno (N-908)

**Fecha:** 2026-10-01 · **De:** Nacho (con Claude) · **Para:** Slatex

## Qué cambió

`carried_package` solo viajaba en el `pick_up` que el host manda a todos al levantar la caja
(`PackageHandling.take_by()`). Quien entraba después (o recargaba tras un reinicio) veía a los compañeros con las
manos vacías, sin pose de carga, y una caja en el regazo de alguien sentado no le reservaba la bahía
(`SeatTending.lap_reserves()`): `CargoSeatPoint._can_board` / `_free_bay` mostraban libres asientos y bahías que el
host tenía reservados.

- `scripts/gameplay/player/player_net_visibility.gd` (tu dominio): `refresh_peer(p, peer_id)` (lo llama
  `Player._on_peer_level_ready`), en el host, después de `sync.update_visibility(peer_id)`, si el jugador tiene
  caja: `p.rpc_id(peer_id, &"pick_up", p.carried_package.get_path())`. Es el **mismo RPC** de siempre
  (`any_peer`, `call_local`, `reliable`, canal 0), solo a ese peer y después del spawn en el mismo canal confiable.
  En la copia que lo recibe `apply_pick_up()` pone la caja en mano y el agarre de los brazos; el clip de levantar
  y el consejo de trampa siguen siendo solo del dueño (`is_local()`).
- `scripts/gameplay/interaction/seat_tending.gd` (tu dominio): `_holder_of()` en el cliente, si ningún jugador
  tiene la caja en `carried_package`, toma como portador al jugador cuya autoridad es `tender_peer_id`, solo
  cuando la caja está en mano (`is_held`) y atada a un regazo (`lap_mount_path`). Una caja sacada de la bahía de
  un sentado por otro conserva su tender pero no tiene `lap_mount_path`: ahí no se adivina.
- `scripts/gameplay/player/player.gd`: solo el comentario de `_on_peer_level_ready` (mismas líneas).
- Tests: `tests/test_late_join_seating.gd` (fase nueva "late carry": reenvío del `pick_up` al peer nuevo y vista
  cliente con la caja en el regazo) y `tests/net_pair.gd` (el host levanta una caja mientras el cliente no está; al
  volver, el cliente la ve en sus manos).

**Ninguna firma cambia, no hay RPC nuevo ni propiedad replicada nueva: `PROTOCOL_VERSION` no sube.** Un cliente
viejo con un host nuevo recibe un `pick_up` más (idempotente); un cliente nuevo con un host viejo se queda con el
respaldo del tender.

## Qué tiene que hacer Slatex

Nada. Si agregás otro estado por jugador que viaje solo en un RPC de una vez (como `pick_up`), reenvialo también
desde `refresh_peer()` para el que entra tarde.

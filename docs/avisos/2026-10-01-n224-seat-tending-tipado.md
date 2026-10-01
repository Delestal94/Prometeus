# `seat_tending.gd` llama a paquete, jugador y asientos con tipos, no por nombre (N-224.4)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`scripts/gameplay/interaction/seat_tending.gd` (`SeatTending`, lógica del host), sin cambio de comportamiento:

- La caja es `DeliveryPackage`, el jugador `Player` y el asiento `CargoSeatPoint`; ya no hay `.call(&"…")`,
  `.get(&"…")` ni `has_method` (de 32 usos por nombre a 0). Los `rpc_id(peer, &"tend_package", …)` siguen por
  nombre, como todos los RPC.
- `scripts/gameplay/interaction/seat_point.gd` gana `class_name CargoSeatPoint` (antes no tenía; el `SeatPoint` del
  módulo no tiene `seated_peer`, `owns_mount` ni `looks_at_mount`). Sus llamadas a `SeatTending` pasan la caja como
  `DeliveryPackage` y `_on_released` usa `tender_peer_id` / `set_tender` directos.
- Firmas: `claim`, `hand_over`, `on_stored`, `mount_of`, `lap_mount_of` y `bind_lap` reciben `DeliveryPackage` (antes
  `Node`); `claim` recibe `CargoSeatPoint`. Los llamadores del repo ya pasaban eso. Los montajes siguen como `Node`
  (`package_mount_point.gd` no tiene class name).
- Los miembros de los grupos `cargo`, `player` y `cargo_seat` que no sean de esos tipos (falsos de test) se saltean con
  `as` en vez de llamarse por nombre.

`tests/test_dynamic_dispatch_budget.gd` suma `seat_tending.gd` a `BUDGETS` con todo en 0.

## Qué tiene que hacer Slatex

Nada. Un asiento nuevo que entre al grupo `cargo_seat` tiene que usar `seat_point.gd` (`CargoSeatPoint`).

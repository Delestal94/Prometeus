# `seat_point.gd` usa tipos para el jugador, la caja y el anclaje (N-224.4)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`scripts/gameplay/interaction/seat_point.gd` (`CargoSeatPoint`, los asientos de la carga), sin cambio de
comportamiento en el juego:

- El jugador se lee como `Player` (`_carried_by()`: `carried_package`); un nodo que no es `Player` (el
  stand-in de `LateJoinSeating`) cuenta como "no carga nada", igual que antes.
- Los anclajes se leen por `preload` de `package_mount_point.gd` (`MountPoint`, sin `class_name`):
  `occupied_by` directo. Un nodo sin ese script (anclajes falsos de un test) cuenta como "sin anclaje".
- La caja como `DeliveryPackage` (`tender_peer_id` directo); `has_method(&"tend_package")` pasa a `is Player`.
  El RPC `tend_package` sigue por nombre, como todo RPC.

`.get(&"…")` 13 → 0 en el archivo. `tests/test_dynamic_dispatch_budget.gd` lo suma a `BUDGETS` con todo en 0.

## Qué tiene que hacer Slatex

Nada. Un asiento cuyo `required_mount_path` o `tend_mount_paths` apunte a un nodo que no sea
`package_mount_point.gd` ahora no lo toma como anclaje.

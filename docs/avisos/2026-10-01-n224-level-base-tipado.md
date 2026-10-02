# `level_base.gd` usa tipos para la ruta, las casas y el camión (N-224.4)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`scripts/gameplay/level_base.gd` (zona compartida: el nivel de entrega), sin cambio de comportamiento ni de RPC:

- `route` es `RouteScript` (preload de `route.gd`, que no tiene `class_name`): `houses`, `goal_lot`, `dresser`,
  `route_length`, `get_progress()`, `assign_packages()` y `crew_house_count()` (estático) se usan directo.
- Las casas son `DeliveryHouse` (`house_index`, `handed_over_open`) y la meta `RouteGoalLot` (`town_name`).
- Las señales `house_resolved` de la ruta y `wrong_package_offered` de cada casa se conectan por la señal; se fue el
  `has_signal(&"house_resolved")` que las protegía (la ruta del nivel siempre es `route.gd`).
- `driver_peer_id` se lee de `vehicle.gd` por preload (`VehicleScript`).
- Una línea larga de `route_progress_changed` partida (la baseline del lint bajó 1).

`tests/test_dynamic_dispatch_budget.gd` suma el archivo a `BUDGETS` con todo en 0 (antes 18 usos por nombre).

## Qué tiene que hacer Slatex

Nada. Si algún día `$World/Route` del nivel de entrega deja de ser `route.gd`, el nivel falla al cargar en vez de
seguir sin casas.

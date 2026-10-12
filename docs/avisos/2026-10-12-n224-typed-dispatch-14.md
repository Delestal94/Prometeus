# `level_common.gd` usa tipos (N-224.4)

**Fecha:** 2026-10-12 · **De:** Nacho · **Para:** Slatex

## Qué cambió

Sin cambio de comportamiento:

- `scripts/gameplay/level_common.gd`: `stop_prediction()` y `set_door_open()` del camión por `VehicleScript`,
  `pick_up()` del jugador de depuración por `Player` y `close_lost_order()` de la ruta por `RouteScript` (preload
  nuevo de `route.gd`, como ya hace `level_base.gd`). `.call` 6 → 1: queda `interact()` del montaje de carga
  (su `InteractionArea` no tiene `class_name`).

`tests/test_dynamic_dispatch_budget.gd` suma el archivo a `BUDGETS`.

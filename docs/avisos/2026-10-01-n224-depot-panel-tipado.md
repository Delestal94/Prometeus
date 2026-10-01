# `depot_panel.gd` usa tipos para el depósito, las cajas y el nivel (N-224.4)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`scripts/ui/depot_panel.gd` (pantalla de las estaciones del depósito), sin cambio de comportamiento en el juego:

- Las señales de `EventBus` (`depot_supplies_changed`, `card_changed`, `shop_opened`, `shop_vote_changed`,
  `shop_resolved`, `run_started`) y `UnlockManager.progress_changed` se conectan directo, como en `hud.gd` y
  `progress_panel.gd` (se fueron los `get_node_or_null("/root/...")`).
- Las compras van a un `Depot` tipado (`_depot_node() -> Depot`: `buy_supply`, `buy_supply_discounted`,
  `team_money`, `supplies`); si el depósito de la estación ya no existe, el del nivel actual como `LevelCommon`.
- Las cajas del grupo `cargo` se leen como `DeliveryPackage` (`package_id`, `is_aboard()`).
- `depot` sigue siendo `Node` y lee `orders` y `boss_notes()` por nombre: `test_depot_panel` le pasa un
  stand-in que no es `Depot`. Un stand-in así ya no compra (antes daba error).

`tests/test_dynamic_dispatch_budget.gd` suma el archivo a `BUDGETS` (call 1, get 1, root 0).

## Qué tiene que hacer Slatex

Nada. Si se renombra algo de lo que la pantalla lee del depósito o de las cajas, ahora falla al compilar.

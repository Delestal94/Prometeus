# `package_pickup_point.gd` usa tipos para la caja, el feedback y el jugador (N-224.4)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`scripts/gameplay/interaction/package_pickup_point.gd` (el `InteractionArea` de cada caja, agarrar y
ayudar a cargar), sin cambio de comportamiento en el juego:

- La caja (el padre) se lee como `DeliveryPackage`: `is_held`, `is_loaded`, `trap_definition`
  (`TrapDefinition`), `assist_available()`, `assist_prompt()`, `can_assist()`, `set_assistant()` y
  `take_by()` directos; se van los `has_method`.
- El feedback hermano como `PackageFeedback` (`highlight()` directo).
- El jugador como `Player` (`carried_package`, `reach_origin()`); un nodo del grupo `player` que no es
  `Player` cuenta como "manos libres" y alcanza desde su posición, igual que antes. El RPC
  `assist_package` sigue por nombre, como todo RPC, y solo se manda a un `Player`.

`.call` 9 → 0 y `.get(&"…")` 3 → 0 en el archivo. `tests/test_dynamic_dispatch_budget.gd` lo suma a
`BUDGETS` con todo en 0.

## Qué tiene que hacer Slatex

Nada. Este `InteractionArea` ahora exige que su padre sea un `DeliveryPackage` (`package.tscn` ya lo es).

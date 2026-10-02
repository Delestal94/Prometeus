# `order_balancer.gd` usa tipos para las trampas y las cajas (N-224.4)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`scripts/gameplay/traps/order_balancer.gd` (el sorteo de pedidos que usa el depósito), sin cambio de
comportamiento en el juego:

- Las trampas se leen como `TrapDefinition` (`id`, `difficulty` directos); por dentro los arrays son
  `Array[TrapDefinition]`. Lo que no es una `TrapDefinition` (un hueco nulo) se salta, como antes.
- Las cajas de `packages_for_order()` se leen como `DeliveryPackage` (`trap_definition`).

`.get(&"…")` 8 → 0 en el archivo. `tests/test_dynamic_dispatch_budget.gd` lo suma a `BUDGETS` con todo
en 0. Las firmas públicas (`build_order`, `packages_for_order`) no cambian.

## Qué tiene que hacer Slatex

Nada. Si algún día se le pasa otra cosa que no sea `TrapDefinition`/`DeliveryPackage`, se ignora.

# `package_feedback.gd` y `package_trap_visuals.gd` usan tipos (N-224.4)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`scripts/gameplay/package/package_feedback.gd` y su helper `package_trap_visuals.gd` (lo que se ve y suena de
cada caja), sin cambio de comportamiento:

- El padre es `DeliveryPackage` (`_package`): `package_id`, `trap_definition` (como `TrapDefinition`),
  `content_definition()` (como `PackageContent`) y `_is_run_active()` se leen directo. `_apply_identity` ya no
  recibe el paquete por argumento (`_apply_identity.call_deferred()`).
- `GameSettings` por la constante `GAME_SETTINGS` (preload de `game_settings.gd`) y el accesor `_settings()`:
  `impact_effects`, `colorblind_palette` y su señal, directos.
- En `package_trap_visuals.gd`, el comportamiento de la trampa como `HostileTrapBehavior`,
  `ExplosiveTrapBehavior` o `LiquidTrapBehavior` (`next_direction()`, `get_state()`, `sequence`,
  `seconds_left`, `spill_amount`…), y el disfraz de evento con `TrapDefinition.localized_name()`.
- Sigue por nombre solo `EventBus` (otros tests lo reemplazan por un `Node`).

`tests/test_dynamic_dispatch_budget.gd` suma los dos archivos a `BUDGETS` (`package_feedback.gd`: root 2, el
resto 0; `package_trap_visuals.gd`: todo 0) y el handle `GAME_SETTINGS` a `SCRIPT_HANDLES`.

## Qué tiene que hacer Slatex

Nada. Si se renombra algo de lo que la caja muestra (campos del paquete, del contenido, de la trampa o de sus
comportamientos), ahora falla al compilar en vez de en el juego.

# `package.gd` llama a trampas, red y jugador con tipos, no por nombre (N-224.4)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`scripts/gameplay/package/package.gd` (`DeliveryPackage`), sin cambio de comportamiento:

- `trap_definition` pasa de `Resource` a `TrapDefinition` y `trap_behavior` de `Resource` a `ITrapBehavior`; las
  llamadas a la trampa (`integrity`, `get_state`, `on_setup`, `on_impact`, `hint_text`, `take_milestones`,
  `create_behavior`, `pick_content`, `name_key`, `id`, `params`) son directas, sin `.call(&"…")` ni `has_method`.
  Un `.tres` o un comportamiento de trampa que no herede de esas clases ya no entra (hoy ninguno lo hace).
- `_reach_origin` usa `Player.reach_origin()` cuando el que agarra es un `Player`.
- Las búsquedas de autoloads pasan a `package_autoloads.gd` (nuevo, `PackageAutoloads`): la red viene tipada como
  `NetSession`; `RunManager`, `CrewProgression` y `RouteEventManager` siguen por nombre porque precargarlos desde el
  paquete rompe la compilación (ciclo y autoloads que todavía no existen). `package.gd` baja de 1000 a 995 líneas.
- Siguen por nombre el camión (los tests meten falsos en el grupo `vehicle`) y el relay de `EventBus`.

`tests/test_dynamic_dispatch_budget.gd` suma `package.gd` y `package_autoloads.gd` a `BUDGETS` y exige que
`NetworkManager` sea un `NetSession`.

## Qué tiene que hacer Slatex

Nada. Si se agrega una trampa nueva, su definición y su comportamiento tienen que heredar de `TrapDefinition` e
`ITrapBehavior` (ya era así en todas).

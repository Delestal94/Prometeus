# `player_sprint.gd` usa tipos para la caja, la sesión y el perfil (N-224.4)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`scripts/gameplay/player/player_sprint.gd` (correr), sin cambio de comportamiento en el juego:

- La caja pesada se reconoce por `trap_definition.id` directo (`TrapDefinition`).
- La semilla del tropezón sale de `world_seed` por la constante `NETWORK_MANAGER` (preload de
  `network_manager.gd`, como en `delivery_house.gd`; `NetSession` no tiene `world_seed`).
- El consejo de la primera corrida usa el perfil como `UnlockProfile` (`mark_tip_seen()` directo).

Sigue por nombre `ground_roughness` de la ruta (grupo `route`: `route.gd` no tiene `class_name` y los
tests ponen suelos falsos en el grupo). `.call` 2 → 1 y `.get(&"…")` 2 → 0 en el archivo;
`tests/test_dynamic_dispatch_budget.gd` lo suma a `BUDGETS` y comprueba que `NETWORK_MANAGER` sea el
script del autoload.

## Qué tiene que hacer Slatex

Nada.

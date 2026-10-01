# `player_cargo_care.gd` usa tipos para el jugador, la caja y los ajustes (N-224.4)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`scripts/gameplay/player/player_cargo_care.gd` (tarjeta de cuidado y práctica del depósito), sin cambio de
comportamiento:

- `player` es `Player` y la caja (`target`) es `DeliveryPackage`: `is_local()`, `_lid_target()`,
  `_gather_package_input()`, `seat_node_path`, `_seated`, `carried_package`, `tended_package`, `care_state` y
  `package_id` se leen directo.
- `GameSettings` por la constante `GAME_SETTINGS` (preload de `game_settings.gd`) y el accesor `_settings()`;
  `UnlockManager` como `UnlockProfile` (`_profile()`); `RunManager` por `PackageAutoloads.run_manager()`.
- Siguen por nombre solo las lecturas de `RunManager` (ciclo de compilación, ver `package_autoloads.gd`).

`tests/test_dynamic_dispatch_budget.gd` suma el archivo a `BUDGETS` (call 1, get 4, root 2) y su handle
`GAME_SETTINGS` a `SCRIPT_HANDLES`.

## Qué tiene que hacer Slatex

Nada. Si se renombra algo de lo que la tarjeta lee del jugador, de la caja o de `GameSettings`, ahora falla al
compilar en vez de en el juego.

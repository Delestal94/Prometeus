# `package_rescue.gd` llama a la trampa, la radio y la red con tipos, no por nombre (N-224.4)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`scripts/gameplay/package/package_rescue.gd` (simulación de cuidado, recuperación y salvataje), sin cambio de
comportamiento:

- Las llamadas al comportamiento de la trampa (`hold_protects`, `wants_road_ahead`, `on_physics_process`,
  `road_jolt_strength`, `cushion_state`, `get_state`, `on_setup`, `care_action`, `hint_text`, `sequence_state`,
  `gesture_state`) son directas sobre `ITrapBehavior`; `params` sale de `TrapDefinition`; la bomba desactivada
  se marca con `ExplosiveTrapBehavior._defused` (antes `.set(&"_defused")`).
- El que sostiene la caja en el regazo se lee como `Player`.
- `RunManager` y `NetworkManager` pasan por `PackageAutoloads` (red tipada como `NetSession`); se van los
  `/root/` sueltos.
- Siguen por nombre: el camión (falsos en el grupo `vehicle`), los métodos de `RunManager` (ciclo de
  compilación, ver `package_autoloads.gd`), `world_seed` (lo declara `network_manager.gd`, no `NetSession`), el
  `seat_node_path` de `view_basis_of` (falsos en el grupo `player`) el anclaje de regazo (sin `class_name`) y el `mode` de la radio (`truck_radio.gd` nombra autoloads
  sin prefijo).

`tests/test_dynamic_dispatch_budget.gd` suma el archivo a `BUDGETS` (call 7, get 6, root 0).

## Qué tiene que hacer Slatex

Nada. Un método nuevo que el rescate le pida a la trampa tiene que declararse en `ITrapBehavior`.

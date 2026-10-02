# `player.gd` usa tipos para la red, el perfil y la caja (N-224.4)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`scripts/gameplay/player/player.gd`, sin cambio de comportamiento en el juego:

- La red se lee como `NetSession` en `_exit_tree` (`is_host()` directo).
- El perfil por un accesor `_profile()` tipado con `UNLOCK_MANAGER` (preload de
  `scripts/core/unlock_manager.gd`, el script del autoload): `selected_cosmetic`, `selected_eyes`,
  `selected_mouth`, `cosmetic_is_auto()`, `cosmetic_color()` y `mark_tip_seen()` directos. `_ready()` llama a
  `_sync_profile_appearance()` en vez de repetir las tres asignaciones.
- `pickup_high_weight_for_package()` recibe un `DeliveryPackage` (su único llamador, `player_carry.gd`, ya
  pasa uno) y llama `get_half_extents()` directo; se fue el valor por defecto para nodos sin ese método.
- El tip de la primera trampa lee `trap_definition.id` directo.

En el archivo: `.call` 5 → 0, `.get(&"…")` 4 → 0, `/root/` 9 → 4 (NetworkManager, UnlockManager y EventBus dos
veces, que sigue por nombre porque un test puede reemplazarlo por un `Node`). `tests/test_dynamic_dispatch_budget.gd`
suma el archivo a `BUDGETS` y su handle `UNLOCK_MANAGER` a `SCRIPT_HANDLES`.

## Qué tiene que hacer Slatex

Nada. Si `UnlockManager` pasa a correr otro script, `test_dynamic_dispatch_budget` avisa.

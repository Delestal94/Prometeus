# `run_session.gd` lee el depósito con tipos (N-224.4)

**Fecha:** 2026-10-02 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`scripts/core/run_session.gd` (la parte de escena del ingreso tardío que salió de `run_manager.gd` con N-225.5),
sin cambio de comportamiento en el juego:

- `depot_door_open()` y `close_depot_door()` leen la escena como `LevelCommon`, el depósito como `Depot` y la
  persiana como `DepotRollerDoor` (`is_open`, `set_open(false, false)`), en un helper `_depot_door()`. Una escena
  que no es un nivel (el menú, la raíz de un test) sigue contando como "puerta abierta" y no se cierra nada.
- Sin cambios de red ni de `PROTOCOL_VERSION`: el estado que manda el anfitrión (`"door_open"`) es el mismo.

En el archivo, 8 → 0 usos por nombre. `tests/test_dynamic_dispatch_budget.gd` lo suma a `BUDGETS` con todo en 0 y
`tests/test_session_sync.gd` comprueba la lectura del anfitrión (abierta y cerrada) y una escena sin nivel.

## Qué tiene que hacer Slatex

Nada. Si un nivel nuevo no hereda de `level_common.gd`, el ingreso tardío no va a sincronizar su persiana.

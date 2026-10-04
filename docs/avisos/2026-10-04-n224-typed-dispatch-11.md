# `late_join_seating.gd`, `player_movement.gd` y `player_nickname.gd` usan tipos (N-224.4)

**Fecha:** 2026-10-04 · **De:** Nacho · **Para:** Slatex

## Qué cambió

Sin cambio de comportamiento:

- `scripts/gameplay/late_join_seating.gd`: los asientos como `CargoSeatPoint` (`pick_seat()` lo devuelve;
  `can_interact`, `unminded_cargo`, `would_displace`, `interact`, `occupant` directos) y `seat_player()` recibe
  un `SeatPoint`. En `level_common.gd` la variable `seat` pasa de `Node` a `SeatPoint`.
- `scripts/gameplay/player/player_movement.gd`: `GameSettings` por la constante `GAME_SETTINGS` (sensibilidad,
  inversión de Y y FOV) y el objetivo de interacción como `Interactable` (`get_prompt()`).
- `scripts/gameplay/player/player_nickname.gd`: `of()` lee el componente como `PlayerNickname`.

`tests/test_dynamic_dispatch_budget.gd` suma los tres a `BUDGETS` y el handle `GAME_SETTINGS` de
`player_movement.gd` a `SCRIPT_HANDLES`.

## Qué tiene que hacer Slatex

Nada. Si se renombra algo de lo que leen estos archivos, ahora falla al compilar en vez de en el juego.

# `player_seat_pose.gd` usa tipos para la cámara, el asiento y la sesión (N-224.4)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`scripts/gameplay/player/player_seat_pose.gd` (subir y bajar de los asientos), sin cambio de
comportamiento en el juego:

- La cámara del asiento se lee como `SeatCamera` (`activate()`/`deactivate()` directos; la del juego,
  `first_person_camera.gd`, la extiende).
- El `InteractionArea` del asiento como `SeatPoint` (`release_occupant()` directo; los asientos del
  camión usan `seat_point.gd`, que lo extiende).
- La sesión como `NetSession` (`is_online()`, `is_host()`).

Lo que no es uno de esos tipos se salta, igual que antes con los `has_method`. El RPC
`release_occupant` al host sigue por `rpc_id`. `.call` 5 → 0 en el archivo;
`tests/test_dynamic_dispatch_budget.gd` lo suma a `BUDGETS`.

## Qué tiene que hacer Slatex

Nada. Una cámara de asiento nueva tiene que extender `SeatCamera` y un asiento nuevo `SeatPoint`
(ya es así en todos).

# `player_interaction.gd` usa tipos para lo que se apunta y la red (N-224.4)

**Fecha:** 2026-10-01 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`scripts/gameplay/player/player_interaction.gd` (apuntar, resaltar, interactuar, ping y carta), sin cambio de
comportamiento ni de RPC:

- Lo que se apunta es `Interactable`: `closest_interactable()` devuelve `Interactable`, `can_interact()` e
  `interact()` se llaman directo y la sonda solo junta `Interactable` (antes, todo lo que tuviera `interact`;
  hoy todos los puntos de interacción del juego lo extienden).
- El empujón de puntería del perro (`aim_bonus`) se lee de `DogDistractPoint`.
- La red como `NetSession` (`_network()`), la vista del contenido de la caja por preload
  (`PACKAGE_CONTENTS_VIEW`, `describe()` directo) y las búsquedas de EventBus en `_bus()`.
- Siguen por nombre `highlight` (lo apuntado no tiene base común), `request_ping` de EventBus y
  `request_use_card` de CrewProgression.
- Dos líneas largas de `is_drop_event` / `is_open_event` partidas (misma lógica).

`tests/test_dynamic_dispatch_budget.gd` suma el archivo a `BUDGETS` (call 3, get 0, root 3; antes 21 usos).

## Qué tiene que hacer Slatex

Nada. Un punto de interacción nuevo tiene que extender `Interactable` (como ya hacen todos) para que la
sonda del jugador lo vea.

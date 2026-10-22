# N-606.4b: el diario suma vuelco, perro y tren (señal local nueva en EventBus)

Zona compartida: `scripts/core/event_bus.gd` suma `signal roadside_moment(kind: StringName, tags: Array)`.
Es **local** (nunca pasa por `EventBus.relay`, no cambia `PROTOCOL_VERSION`): cada peer oye su propia copia y
solo el `RunChronicle` del host escribe el diario.

- `kind = &"dog_chase"`: lo emite `ChasingDog` al empezar a perseguir y otra vez con `["honked"]` si la
  bocina lo manda a casa.
- `kind = &"train_stop"`: lo emite `RailCrossingSegment` en el host cuando el tren termina de pasar con el
  camión esperando del lado de llegada, a ≤ 35 m de las vías (`WAIT_RANGE`).
- El vuelco no usa la señal: `RunChronicle.compose` lo saca del `reason` de los resultados (`HUD_RUN_TIPPED`)
  y reemplaza a `run_failed` en una entrega y a `endless_end` en Endless (las dos son de policiales: el diario imprimiría una sola).

Slatex: si un sistema tuyo quiere salir en el diario, emití `roadside_moment` con un `kind` nuevo y sumalo a
`RunChronicle.ROADSIDE_KINDS` y a `data/newspaper/stories.json` (con sus claves en `strings_ui.csv`).

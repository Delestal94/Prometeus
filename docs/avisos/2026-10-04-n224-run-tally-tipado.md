# `run_tally.gd` sin despacho por nombre; `hud_pause.gd` le pasa el registro (N-224.4)

**Fecha:** 2026-10-04 · **De:** Nacho · **Para:** Slatex

## Qué cambió

`scripts/core/run_tally.gd` (el resumen de la corrida en la pantalla de "se fue el anfitrión", N-222), sin cambio
de comportamiento en el juego:

- `RunTally.has_unfinished_run(run)` y `RunTally.of(run)` (leían `RunManager` por nombre) pasan a
  `RunTally.unfinished(results, elapsed_seconds)` y `RunTally.count(deliveries, cargo, endless, expected_houses,
  distance, elapsed_seconds)`, con argumentos tipados. `handed_over()` sale de `run_deliveries.gd` por `preload`.
  `run_manager.gd` no se puede precargar desde acá (nombra autoloads; `net_trio.gd` carga este archivo por
  `--script`) y ya tiene 20 métodos públicos (tope del lint), así que no ganó ninguno.
- **`scripts/ui/hud/hud_pause.gd`** (tuyo): `_on_connection_lost()` arma el resumen con un helper nuevo,
  `_unfinished_tally()`, que lee el autoload `RunManager` tipado y devuelve `{}` si no hay corrida empezada o ya
  llegaron resultados. El texto en pantalla es el mismo.
- Sin cambios de red ni de `PROTOCOL_VERSION`.

En `run_tally.gd`, 9 → 0 usos por nombre. `tests/test_dynamic_dispatch_budget.gd` lo suma a `BUDGETS` con todo en
0; `tests/test_host_gone_tally.gd` usa la API nueva y suma el caso "con resultados ya no está sin terminar";
`tests/net_trio.gd` igual.

## Qué tiene que hacer Slatex

Nada, salvo que tengas código propio que llame a `RunTally.of()` o `has_unfinished_run()`: cambialo por
`count()`/`unfinished()` con los campos de `RunManager` (como `_unfinished_tally()` en `hud_pause.gd`).

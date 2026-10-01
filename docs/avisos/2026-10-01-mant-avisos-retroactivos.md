# Aviso: retroactivos de la semana y docs del mantenimiento (2026-10-01)

El mantenimiento semanal encontró dos PRs que tocaron la zona compartida sin aviso, y en el mismo PR
arregló docs de la zona compartida y del dominio de Slatex.

## #119 · N-219 (zona compartida: `modules/route_gen/`)

- `route_segment.gd`: los `PackedScene` de cada modelo se guardan en un caché estático (`_scenes`) y
  `RouteSegment.warm_models(paths)` los carga de antemano mientras se arma el nivel. Antes cada baranda,
  poste o módulo de puente releía el archivo en el tick de física que lo creaba.
- `segment_streamer.gd`: el `DressingBatcher` ya no fusiona la geometría en el mismo tick en que nace el
  tramo; queda en `_unbatched` y se fusiona uno por tick sin spawn. `flush_batches()` fusiona todo lo
  pendiente de una vez (arranque del nivel, tests). Un test que mire la geometría fusionada justo después
  de un spawn tiene que llamar `flush_batches()`.
- Test: `modules/route_gen/tests/test_route_gen.gd` y `tests/test_endless_physics_spike.gd`.

## #106 · N-228.1 (zona compartida: `README.md`)

Solo texto: el tope de jugadores pasó de 5 a 8 (1 conduce, hasta 7 llevan paquete).

## Este PR (mantenimiento)

- `README.md` (compartida): la sección de tests describe el `pre-push` actual (lint, `check_modules` y solo
  los tests afectados; `FULL_TESTS=1` / `SKIP_TESTS=1`) y la batería completa de CI en cuatro runners.
- `docs/controles-y-ui.md` (Slatex): dos referencias a `prototype_hud.gd`, que ya no existe, apuntan a
  `scripts/ui/hud/hud.gd` y `scripts/ui/hud/hud_results.gd`. Sin cambio de contenido.
